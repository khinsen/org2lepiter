# org2lepiter

Export org-mode files and org-roam databases to Lepiter notes/databases

For now, this is a big code snippet developed for my personal use. It exports a complete org-roam database (v1, the in-progress v2 is not supported at all) into a Lepiter v3 database, i.e. a directory containing JSON files. Edit the file to adapt it to your setup, and then run `M-x eval-buffer`.

Note that the export handles only a small subset of org-mode markup. Mapping everything to Lepiter is not trivial and probably not very useful either.

Note also that the code as it is requires the org-roam database to be version controlled via git. It uses the git history to construct the modification time stamps that Lepiter stores with each page (and even snippet).

Dependencies (all available via MELPA):
 - [dash.el](https://github.com/magnars/dash.el)
 - [ox-json](https://github.com/jlumpe/ox-json)
 - [uuidgen-el](https://github.com/kanru/uuidgen-el)
 - `git` must be on your `$PATH`
