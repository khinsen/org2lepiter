(require 'ox-json)
(require 'dash)
(require 'uuidgen)

;; The directory to which the Lepiter pages are written
(setq lepiter-v4-database-directory "~/Repos/lepiter/org-roam/")

;; The author e-mail in exported Lepiter snippets
(setq lepiter-export-email "author@mail.org")

;; A valid namespace UUID according to RFC4122 Appendix C.
;; Used to construct Lepiter snippet UUIDs.
(setq lepiter-namespace-uuid "3680b78b-8c79-4f19-af13-c0103db9b2a2")

;; The list of pages to be exported. All pages by default, modify to exclude pages.
(defun lepiter-org-roam-pages-for-export ()
  (org-roam--list-all-files))

;; Given the filename of a file in the org-roam database,
;; construct its title in the Lepiter database.
(defun lepiter-title-for-file (filename)
  (let* ((full-name (expand-file-name (concat org-roam-directory filename)))
         (title (org-roam-db-query
                 [:select title :from titles
                  :where (= file $s1)
                  :limit 1]
                 full-name)))
    (and title
         (caar title))))

;; Translate links, distinguishing between file links inside the org-roam
;; database and links to outside resources.
(defun lepiter-export-link (node)
  (let* ((properties (alist-get 'properties node))
         (link-type (alist-get 'type properties))
         (post-blank (make-string (alist-get 'post-blank properties) 32)))
    (cond
     ((equal link-type "file")
      (concat "[["
              (lepiter-title-for-file (alist-get 'path properties))
              "]]"
              post-blank))
     ((member link-type '("http" "https"))
      (let* ((link (alist-get 'raw-link properties))
             (link-text (lepiter-format-text (alist-get 'contents node)))
             (link-text (if (string-empty-p link-text) link link-text)))
        (concat "[" link-text "](" link  ")" post-blank)))
     (t
      (concat (alist-get 'raw-link properties) ":"
              (lepiter-format-text (alist-get 'contents node))
              post-blank)))))

;; Translate text sections, possibly containing links, to Lepiter Markdown.
(defun lepiter-item-to-text (item)
  (cond
   ((stringp item) item)
   ((not (listp item))
    (message "%s" item)
    (error "non-string items should be lists"))
   ((not (equal (alist-get '$$data_type item) "org-node"))
    (message "%s" item)
    (error "lists should represent org-nodes"))
   ((equal (alist-get 'type item) "link")
    (lepiter-export-link item))))

(defun lepiter-format-text (items)
  (seq-reduce #'concat (seq-map #'lepiter-item-to-text items) ""))

;; Construct a valid random UID for Lepiter
(defun lepiter-make-uid ()
  (let ((bytes (make-string 6 0)))
    (dotimes (i (length bytes))
      (aset bytes i (random 256)))
    (base64-encode-string bytes)))

;; Translate an Emacs time stamp to an ISO time stamp.
(defun lepiter-iso-time-stamp (time)
  (let* ((time-zone (format-time-string "%z" time))
         (iso-time-zone (concat (substring time-zone 0 3) ":" (substring time-zone 3 5)))
         (iso-time (format-time-string "%Y-%m-%dT%T" time)))
    (concat iso-time iso-time-zone)))

;; Construct the JSON representation of a time stamp.
(defun lepiter-v4-time-stamp (time)
  (let* ((iso-stamp (lepiter-iso-time-stamp time)))
    `((__type . "time")
      (time . ((__type . "dateAndTime")
      (dateAndTimeString . ,iso-stamp))))))

;; Retrieve initial and last modification time stamps via git.
(defun lepiter-v4-first-revision-time-stamp (filename)
  (--> filename
       (concat "git -C " org-roam-directory " log --format=%at -- " it " | tail -1")
       shell-command-to-string
       string-to-number
       lepiter-v4-time-stamp))

(defun lepiter-v4-last-revision-time-stamp (filename)
  (--> filename
       (concat "git -C " org-roam-directory " log --format=%at -- " it " | head -1")
       shell-command-to-string
       string-to-number
       lepiter-v4-time-stamp))

;; Construct JSON data structures for page/snippet metadata
(defun lepiter-v4-email (string)
  `((__type . "email")
    (emailString . ,string)))

(defun lepiter-v4-make-uid ()
  `((__type . "uid")
    (uidString . ,(lepiter-make-uid))))

(defun lepiter-v4-add-node-metadata (node-alist)
  (let ((children (alist-get 'children node-alist))
        (meta `((createTime . ,lepiter-create-time)
                (createEmail . ,(lepiter-v4-email lepiter-export-email))
                (editTime . ,lepiter-edit-time)
                (editEmail . ,(lepiter-v4-email lepiter-export-email))
                (uid . ,(lepiter-v4-make-uid)))))
    (if children
        (let* ((children-with-meta
                (mapcar #'lepiter-v4-add-node-metadata children))
               (nodes-without-children
                (--remove (equal (car it) 'children) node-alist)))
          (append meta
                  `((children .
                              ((__type . "snippets")
                               (items . ,(vconcat children-with-meta)))))
                  nodes-without-children))
      (append meta node-alist))))

(defun lepiter-v4-add-page-metadata (title uuid node-alist)
  (append
   `((__schema . "4.1")
     (__type . "page")
     (pageType . ((__type . "namedPage")
                  (title . ,title)))
     (uid . ((__type . "uuid")
             (uuid . ,uuid))))
   (--remove (equal (car it) 'uid) node-alist)))

;; Translate an org-roam page into a Lepiter page.
(defun lepiter-v4-format-title (item)
  (let* ((properties (alist-get 'properties item))
         (title (alist-get 'title properties)))
    (and title
         (lepiter-format-text title))))

(defun lepiter-v4-org-item (item)
  (cond
   ((stringp item)
    (list (s-chomp item)))
   ((not (listp item))
    (message "%s" item)
    (error "non-string items should be lists"))
   ((not (equal (alist-get '$$data_type item) "org-node"))
    (message "%s" item)
    (error "lists should represent org-nodes"))
   (t
    (let ((type (alist-get 'type item))
          (ref (alist-get 'ref item))
          (properties (alist-get 'properties item))
          (title (lepiter-v4-format-title item))
          (contents (apply #'append (mapcar #'lepiter-v4-org-item (alist-get 'contents item)))))
      (cond
       ((equal type "section")
        (--filter it contents))
       ((equal type "headline")
        (list `((__type . "textSnippet")
                (string . ,title)
                (paragraphStyle . ((__type . "textStyle")))
                (children . ,(vconcat contents)))))
       ((equal type "paragraph")
        (list `((__type . "textSnippet")
                (string . ,(apply #'concat (--filter it contents)))
                (paragraphStyle . ((__type . "textStyle")))
                (children . []))))
       ((equal type "keyword")
        (let ((key (alist-get 'key properties)))
          (cond
           ((equal key "ROAM_KEY")
            (let ((link (alist-get 'value properties)))
              (list `((__type . "textSnippet")
                      (string . ,(concat "URL: [" link "](" link  ")"))
                      (paragraphStyle . ((__type . "textStyle")))
                      (children . [])))))
           (t nil))))
       ((equal type "link")
        (list (lepiter-export-link item)))
       ((equal type "src-block")
        (let* ((org-language (alist-get 'language properties)))
          (cond
           ((string-equal org-language "pharo")
            (list `((__type . "pharoSnippet")
                    (code . ,(s-trim-right (alist-get 'value properties)))
                    (children . []))))
           ((string-equal org-language "python")
            (list `((__type . "pythonSnippet")
                    (code . ,(s-trim-right (alist-get 'value properties)))
                    (children . []))))
           ((string-equal org-language "js")
            (list `((__type . "javascriptSnippet")
                    (code . ,(s-trim-right (alist-get 'value properties)))
                    (children . []))))
           (t
            (list `((__type . "codeSnippet")
                    (code . ,(s-trim-right (alist-get 'value properties)))
                    (language . ,org-language)
                    (children . [])))))))
       ((equal type "quote-block")
        (list `((__type . "textSnippet")
                (string . "Quote")
                (paragraphStyle . ((__type . "textStyle")))
                (children . ,(vconcat contents)))))
       ((equal type "plain-list")
        (--filter it contents))
       ((equal type "item")
        (--filter it contents))
       (t nil))))))

(defun lepiter-v4-org-as-json (buffer)
  (with-current-buffer buffer
    (let* ((org-export-with-sub-superscripts nil)
           (org-export-use-babel nil)
           (json-buffer (ox-json-export-to-buffer)))
      (with-current-buffer json-buffer
        (goto-char 1)
        (json-read)))))

(defun lepiter-v4-filename-for-uuid (uuid)
  (concat (org-id-int-to-b36
           (-reduce-from (lambda (acc char) (+ (* acc 256) char)) 0
                         (string-to-list (uuidgen--decode uuid))))
          ".lepiter"))

(defun lepiter-export-page-to-v4-format (page)
  (let* ((buffer (find-file-noselect page))
         (document (lepiter-v4-org-as-json buffer))
          (properties (alist-get 'properties document))
         (contents (alist-get 'contents document))
         (lepiter-create-time (lepiter-v4-first-revision-time-stamp page))
         (lepiter-edit-time (lepiter-v4-last-revision-time-stamp page))
         (org-items (apply #'append (mapcar #'lepiter-v4-org-item contents)))
         (page-title (lepiter-v4-format-title document))
         (page-uuid (uuidgen-3 lepiter-namespace-uuid page-title))
         (lepiter-page
          (lepiter-v4-add-page-metadata
           page-title page-uuid
           (lepiter-v4-add-node-metadata
            `((children . ,(vconcat org-items))))))
         (filename (lepiter-v4-filename-for-uuid page-uuid)))
    (write-region
     (json-encode lepiter-page) nil
     (concat lepiter-v4-database-directory filename))))

;; Iterate over all pages in the org-roam database
(save-window-excursion
  (dolist (page (lepiter-org-roam-pages-for-export))
    (message "Processing %s" page)
    (lepiter-export-page-to-v4-format page)))

;; Write the database properties file
(let ((db-properties
       `((uuid . ,lepiter-namespace-uuid)
         (schema . "4.1")
         (databaseName . "org-roam"))))
  (write-region
   (json-encode db-properties) nil
   (concat lepiter-v4-database-directory "lepiter.properties")))
