# org2lepiter

Export org-mode files and org-roam databases to Lepiter notes/databases

For now, this is a big code snippet developed for my personal use. It exports a complete org-roam v2 database into a Lepiter vv4 database, i.e. a directory containing JSON files. Edit the file to adapt it to your setup, and then run `M-x eval-buffer`.

Note that the export handles only a small subset of org-mode markup. Mapping everything to Lepiter is not trivial and probably not very useful either. Perhaps the most important limitation is that only file nodes are handled correctly. Headline nodes are exported as simple headlines, and links to headline nodes probably cause a crash at export time (as you may have guessed, I don't use headline nodes).

Note also that the code as it is requires the org-roam database to be version controlled via git. It uses the git history to construct the modification time stamps that Lepiter stores with each page (and even snippet).

If you still use version 1.x of org-roam, use [this commit](https://github.com/khinsen/org2lepiter/commit/dec48825a08279e59c72671773316b78a76b078a), which contains the latest version of this code for org-roam v1.

Dependencies (all available via MELPA):
 - [org-roam](https://github.com/org-roam/org-roam/)
 - [dash.el](https://github.com/magnars/dash.el)
 - [ox-json](https://github.com/jlumpe/ox-json)
 - [uuidgen-el](https://github.com/kanru/uuidgen-el)
 - `git` must be on your `$PATH`
