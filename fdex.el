;;; fdex.el --- file indexing library
;;; -*- lexical-binding: t -*-
;; 
;; Copyright © 2016 Mola-T <Mola@molamola.xyz>
;;
;; Author: Mola-T <Mola@molamola.xyz>
;; URL: https://github.com/mola-T/fdex
;; Version: 1.0
;; Package-Requires: ((cl-lib.el "0.5"))
;; Keywords: file
;;
;; This file is NOT part of GNU Emacs.
;;
;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 3, or (at your option)
;; any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to the
;; Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.
;;
;;; Commentary:
;; This package provides functions to indexing folders an files.
;; See README for more details.
;;
;;; code:
(require 'cl-lib)

(defconst fdex-ROOTNODE ""
  "NodeID for root.")
(defconst fdex-CONTROLNODE 0
  "NodeID for fdexControl.")

(cl-defstruct fdexControl
  rootPath                 ;; Path to index root
  (pendingUpdate nil)      ;; List of pending update nodeID
  (pendingRemove nil)      ;; List of pending remove nodeID
  (priorityUpdate nil)     ;; List of priority update nodeID
  (exclude nil)            ;; A single string of regexp to exclude files or folders from indexing
  (whitelist nil)          ;; A single string of regexp to whitelist files or folders form exclude
  )

(cl-defstruct fdexNode
  nodeID                   ;; nodeID is the path relative to index root. Root node is 0.

  (updateTime '(0 0 0 0))  ;; Time that last update this node
  childrenNode             ;; List of subfolder nodeID
  filelist                 ;; List of files under nodeID
  )



;;; Core function
(defun fdex-modify-time (path)
  "This function is not inteneded to be called by user!

Return last modify time from PATH.
PATH can be a file path or a folder path.
If PATH does not exist, return nil.

Return
Type:\t\t Emacs time list or nil
Descrip.:\t Emacs time list represent time as a list of either four integers
\t\t\t (sec-high sec-low microsec picosec).
\t\t\t If path does not exists, return nil.

PATH
Type:\t\t string
Descrip.:\t String of path to file or folder."
  (nth 5 (file-attributes path)))

(defun fdex-string-predicate (entry1 entry2)
  "This function is not inteneded to be called by user!

Wrapper of `string-lessp' to sort ENTRY regardless of case.

Return
Type:\t\t bool
Descrip.:\t t if ENTRY1 is less than ENTRY2.

ENTRY1 ENTRY2
Type:\t\t string
Descrip.:\t Any string.  Intend to use for file or folder path."
  (string-lessp (downcase entry1) (downcase entry2)))

(defun fdex-folder-index-p (path folder &optional exclude whitelist)
  "This function is not inteneded to be called by user!

Predicate whether FOLDER under PATH should be indexed.
If EXCLUDE or WHITELIST are provided, they will be taken into account.

Return
Type:\t\t bool
Descrip.\t Return t if FOLDER should be indexed, otherwise nil.

PATH
Type:\t\t string
Descrip.\t String of path to FOLDER.

FOLDER
Type:\t\t string
Descrip.\t String of a single entry under PATH.

EXCLUDE
Type:\t\t string
Descrip.\t String of regexp to exclude FOLDER from indexing.

WHITELIST
Type:\t\t string
Descrip.\t String of regexp to whitelist an excluded FOLDER."
  (catch 'false
    (let ((fullpath (concat path folder)))

      ;; check folder accessibility
      (unless (and (file-readable-p fullpath) (file-executable-p fullpath))
        (throw 'false nil))

      ;; Handle dot and dotdot
      (when (or (string= folder ".") (string= folder ".."))
        (throw 'false nil))
      
      ;; Handle symlink to parent directory
      (when (and (file-symlink-p fullpath)
                 (or (string= (file-symlink-p fullpath) "..")
                     (string-prefix-p (file-symlink-p fullpath) path)))
        (throw 'false nil))
      
      ;; Handle exclude and whitelist
      (when (and exclude (string-match exclude path))
        (unless (and whitelist (string-match whitelist path))
          (throw 'false nil)))

      t)))

(defun fdex-file-index-p (path file &optional exclude whitelist)
  "This function is not inteneded to be called by user!

Predicate whether FILE under PATH should be indexed.
If EXCLUDE or WHITELIST are provided, they will be taken into account.

Return
Type:\t\t bool
Descrip.\t Return t if FILE should be indexed, otherwise nil.

PATH
Type:\t\t string
Descrip.\t String of path to FILE.

FILE
Type:\t\t string
Descrip.\t String of a single entry under PATH.

EXCLUDE
Type:\t\t string
Descrip.\t String of regexp to exclude FILE from indexing.

WHITELIST
Type:\t\t string
Descrip.\t String of regexp to whitelist an excluded FILE."
  (catch 'false
    (let ((fullpath (concat path file)))

      ;; check folder accessibility
      (unless (file-readable-p fullpath)
        (throw 'false nil))
      
      ;; Handle exclude and whitelist
      (when (and exclude (string-match exclude path))
        (unless (and whitelist (string-match whitelist path))
          (throw 'false nil)))

      t)))


(defun fdex-updateNode (nodehash nodeID &optional priority)
  "This function is not inteneded to be called by user!

Update node specified by NODEID in NODEHASH.
PRIORITY can be set to t to indicate the node update is called in priority.
The children nodes of the current node
will also be set to priority update next time.
The PRIORITY is only valid for one time.

NODEHASH
Type:\t\t hashtable
Descrip.:\t A hashtable created by `fdex-new'

NODEID
Type:\t\t NODEID
Descrip.:\t This is a internal maintained variable to denote a node."
  (let* ((control (gethash fdex-CONTROLNODE nodehash))
         (node (gethash nodeID nodehash))
         (rootPath (fdexControl-rootPath control))
         (currentPath (concat rootPath nodeID)))

    (catch 'terminate
      ;; Check whether this node exists
      (unless (file-directory-p currentPath)
        (setf (fdexControl-pendingRemove control) (append (fdexControl-pendingRemove control) (list nodeID)))
        (throw 'terminate t))

      ;; Check whether this node need to be updated
      (when (time-less-p (fdex-modify-time currentPath) (fdexNode-updateTime node))
        (setf (fdexControl-pendingUpdate control) (append (fdexControl-pendingUpdate control)(fdexNode-childrenNode node)))
        (throw 'terminate t))

      (let ((contents (directory-files currentPath nil nil 'NOSORT))
            (exclude (fdexControl-exclude control))
            (whitelist (fdexControl-whitelist control))
            (childrenNodes (fdexNode-childrenNode node))
            (childrenNodes-new (fdexNode-childrenNode node))
            (current-folderlist nil)
            (current-filelist nil))
        
        ;; Check if any entry of children nodes need to be removed
        (dolist (childrenNode childrenNodes)
          (let ((childrenNode-path (concat rootPath childrenNode)))
            (unless (and (file-exists-p childrenNode-path) (file-directory-p childrenNode-path))
              (setq childrenNodes-new (delete childrenNode childrenNodes-new))
              (setf (fdexControl-pendingRemove control) (append (list childrenNode) (fdexControl-pendingRemove control))))))

        ;; Seperate folder and files in contents
        ;; Put them in current-folderlist and current-filelist
        (dolist (content contents)
          (if (file-directory-p (concat currentPath content))
              (when (fdex-folder-index-p currentPath content exclude whitelist)
                (setq current-folderlist (nconc (list (file-name-as-directory content)) current-folderlist)))
            (when (fdex-file-index-p currentPath content exclude whitelist)
              (setq current-filelist (nconc (list content) current-filelist)))))

        ;; Check if there is any newly added folder by comparing current-folderlist and node-folderlist
        (dolist (folder current-folderlist)
          (unless (member (file-name-as-directory (concat (fdexNode-nodeID node) folder)) childrenNodes-new)
            (let ((newnode (make-fdexNode :nodeID (file-name-as-directory (concat (fdexNode-nodeID node) folder)))))
              (setq childrenNodes-new (append (list (file-name-as-directory (concat (fdexNode-nodeID node) folder))) childrenNodes-new))
              (puthash (file-name-as-directory (concat (fdexNode-nodeID node) folder)) newnode nodehash)
              (if priority
                  (setf (fdexControl-priorityUpdate control)
                        (append (fdexControl-priorityUpdate control) (list (file-name-as-directory (concat (fdexNode-nodeID node) folder)))))
                (setf (fdexControl-pendingUpdate control)
                      (append (fdexControl-pendingUpdate control) (list (file-name-as-directory (concat (fdexNode-nodeID node) folder)))))))))

        ;; Sort current-filelist and childrenNodes
        (setq current-filelist (sort current-filelist 'fdex-string-predicate)
              childrenNodes-new (sort childrenNodes-new 'fdex-string-predicate))

        (setf (fdexNode-childrenNode node) childrenNodes-new
              (fdexNode-filelist node) current-filelist
              (fdexNode-updateTime node) (current-time)))

      t)))

(defun fdex-removeNode (nodehash nodeID)
  "This function is not inteneded to be called by user!

Remove the node specified by NODEID from NODEHASH.
The children nodes of the removing node will be put in pending remove.

NODEHASH
Type:\t\t hashtable
Descrip.:\t A hashtable created by `fdex-new'

NODEID
Type:\t\t NODEID
Descrip.:\t This is a internal maintained variable to denote a node."
  (let ((node (gethash nodeID nodehash))
        (control (gethash fdex-CONTROLNODE nodehash)))
    (when node
      (setf (fdexControl-pendingRemove control)
            (append (fdexNode-childrenNode node) (fdexControl-pendingRemove control))))
    (remhash nodeID nodehash))
  t)



;;; User function
;;;###autoload
(defun fdex-new (path &optional exclude whitelist)
  "Create and return a hashtable for future indexing under PATH.
EXCULDE and WHITELIST can be provided to filter indexing result.

Return
Type:\t\t hashtable
Descrip.:\t A new hash table which can be use for indexing files from PATH.

PATH
Type:\t\t string
Descrip.:\t String of path to be the index root.

EXCLUDE
Type:\t\t string
Descrip.:\t String of regexp to filter index files.

WHITELIST
Type:\t\t string
Descrip.:\t String of regexp to prevent files from filtering out."
  
  (let ((nodehash (make-hash-table :test 'equal :size 200 ))
        (control (make-fdexControl))
        (node (make-fdexNode :nodeID fdex-ROOTNODE)))
    
    ;; Put root and control into hash
    (setf (fdexControl-rootPath control) (file-name-as-directory path)
          (fdexControl-exclude control) exclude
          (fdexControl-whitelist control) whitelist)
    
    (puthash fdex-CONTROLNODE control nodehash)
    (puthash fdex-ROOTNODE node nodehash)

    nodehash))

;;;###autoload
(defun fdex-update (nodehash)
  "Update the whole file indexing hashtable NODEHASH.
It is a blocking function.
If number of folders and files to be indexed is large,
Emacs will be freezed up.

NODEHASH
Type:\t\t hashtable
Descrip.:\t A hashtable created by `fdex-new'"
  (let ((control (gethash fdex-CONTROLNODE nodehash)))

    ;; Update node
    (setf (fdexControl-pendingUpdate control) nil)
    (fdex-updateNode nodehash fdex-ROOTNODE)
    (while (car-safe (fdexControl-pendingUpdate control))
      (let ((updateNode (car (fdexControl-pendingUpdate control))))
        (setf (fdexControl-pendingUpdate control) (cdr (fdexControl-pendingUpdate control)))
        (fdex-updateNode nodehash updateNode)))

    ;; Remove node
    (while (car-safe (fdexControl-pendingRemove control))
      (let ((removeNode (car (fdexControl-pendingRemove control))))
        (setf (fdexControl-pendingRemove control) (cdr (fdexControl-pendingRemove control)))
        (fdex-removeNode nodehash removeNode))))
  t)

;;;###autoload
(defun fdex-updateRoot (nodehash)
  "Update the root node in NODEHASH.

NODEHASH
Type:\t\t hashtable
Descrip.:\t A hashtable created by `fdex-new'"
  (fdex-updateNode nodehash fdex-ROOTNODE))

;;;###autoload
(defun fdex-updateNext (nodehash)
  "Update next node in NODEHASH.
\"Next node\" is determined by fdex.
It may be removing a node, adding a node or updating a node.
If there is still node to be updated, this function returns t.
If updateNext reaches the end, it returns nil.

Return
Type:\t\t bool
Descrip.:\t t if there is next node to be updated.
\t\t\t nil if updateNext reaches the end.

NODEHASH
Type:\t\t hashtable
Descrip.:\t A hashtable created by `fdex-new'"
  (let ((control (gethash fdex-CONTROLNODE nodehash)))
    (cond
     ((car-safe (fdexControl-pendingRemove control))
      (let ((removeNode (car (fdexControl-pendingRemove control))))
        (setf (fdexControl-pendingRemove control) (cdr (fdexControl-pendingRemove control)))
        (fdex-removeNode nodehash removeNode))
      t)
     ((car-safe (fdexControl-priorityUpdate control))
      (let ((updateNode (car (fdexControl-priorityUpdate control))))
        (setf (fdexControl-priorityUpdate control) (cdr (fdexControl-priorityUpdate control)))
        (fdex-updateNode nodehash updateNode t))
      t)
     ((car-safe (fdexControl-pendingUpdate control))
      (let ((updateNode (car (fdexControl-pendingUpdate control))))
        (setf (fdexControl-pendingUpdate control) (cdr (fdexControl-pendingUpdate control)))
        (fdex-updateNode nodehash updateNode))
      t)
     ;; default
     (t nil))))

;;;###autoload
(defun fdex-add-priority-update-path (nodehash path)
  "Add PATH to priority update in NODEHASH.

NODEHASH
Type:\t\t hashtable
Descrip.:\t A hashtable created by `fdex-new'

PATH
Type:\t\t string
Descrip.:\t A string to path."
  (let* ((control (gethash fdex-CONTROLNODE nodehash))
         (rootPath (fdexControl-rootPath control))
         nodeID)
    (when (and (file-exists-p path) (string-prefix-p rootPath path))
      (setq path (file-name-directory (directory-file-name (file-name-as-directory path))))
      (string-match rootPath path)
      (setq nodeID (substring path (match-end 0)))
      (while (and nodeID (not (gethash nodeID nodehash)))
        (setq nodeID (file-name-directory (directory-file-name nodeID))))
      (when nodeID
        (setf (fdexControl-priorityUpdate control) (append (fdexControl-priorityUpdate control) (list nodeID)))))))

;;;###autoload
(defun fdex-get-filelist (nodehash &optional full)
  "Get a list of files under NODEHASH.
If FULL is t, the list contains full path.
If FULL is nil, the list contains path relative to index root.

Return
Type:\t\t string list
Descrip.:\t A list of string of files in NODENASH

NODEHASH
Type:\t\t hashtable
Descrip.:\t A hashtable created by `fdex-new'

FULL
Type:\t\t bool
Descrip.:\t t for full file path, nil for path relative to index root."
  (let ((folderlist nil)
        (filelist nil))

    ;; Get filelist and folder list from root nodes
    (setq filelist  (mapcar (apply-partially 'concat (and full (fdexControl-rootPath (gethash fdex-CONTROLNODE nodehash))))
                            (fdexNode-filelist (gethash fdex-ROOTNODE nodehash))))
    (setq folderlist (append (fdexNode-childrenNode (gethash fdex-ROOTNODE nodehash)) folderlist))

    (while (car-safe folderlist)
      (let ((folder (car folderlist)))
        (setq folderlist (cdr folderlist))
        (setq filelist (append filelist
                               (mapcar (apply-partially 'concat (and full (fdexControl-rootPath (gethash fdex-CONTROLNODE nodehash))) folder)
                                       (fdexNode-filelist (gethash folder nodehash)))))
        (setq folderlist (append (fdexNode-childrenNode (gethash folder nodehash)) folderlist))))
    filelist))

;;;###autoload
(defun fdex-get-folderlist (nodehash &optional full)
  "Get a list of folders under NODEHASH.
If FULL is t, the list contains full path.
If FULL is nil, the list contains path relative to index root.

Return
Type:\t\t string list
Descrip.:\t A list of string of folder in NODENASH

NODEHASH
Type:\t\t hashtable
Descrip.:\t A hashtable created by `fdex-new'

FULL
Type:\t\t bool
Descrip.:\t t for full file path, nil for path relative to index root."
  (let ((nodelist nil)
        (folderlist nil))

    ;; Get folderlist and folder list from root nodes
    (setq folderlist (list (or (and full (fdexControl-rootPath (gethash fdex-CONTROLNODE nodehash))) "INDEXROOT")))
    (setq nodelist (append (fdexNode-childrenNode (gethash fdex-ROOTNODE nodehash)) nodelist))

    (while (car-safe nodelist)
      (let ((folder (car nodelist)))
        (setq nodelist (cdr nodelist))
        (setq nodelist (append (fdexNode-childrenNode (gethash folder nodehash)) nodelist))
        (setq folderlist (append folderlist
                                 (list (concat (and full (fdexControl-rootPath (gethash fdex-CONTROLNODE nodehash))) folder))))))
    folderlist))

;;;###autoload
(defun fdex-get-rootPath (nodehash)
  "Obtain root path of NODEHASH.

Return
Type:\t\t string
Descrip.:\t String of path to index root.

NODEHASH
Type:\t\t hashtable
Descrip.:\t A hashtable created by `fdex-new'"
  (fdexControl-rootPath (gethash fdex-CONTROLNODE nodehash)))

;;;###autoload
(defun fdex-get-exclude (nodehash)
  "Get a regexp of exclude from NODEHASH.

Return
Type:\t\t string
Descrip.:\t A string of regexp which the file indexing excluded.

NODEHASH
Type:\t\t hashtable
Descrip.:\t A hashtable created by `fdex-new'"
  (fdexControl-exclude (gethash fdex-CONTROLNODE nodehash)))

;;;###autoload
(defun fdex-get-whitelist (nodehash)
  "Get a regexp of whitelist from NODEHASH.

Return
Type:\t\t string
Descrip.:\t A string of regexp which the file indexing whitelisted.

NODEHASH
Type:\t\t hashtable
Descrip.:\t A hashtable created by `fdex-new'"
  (fdexControl-whitelist (gethash fdex-CONTROLNODE nodehash)))

(provide 'fdex)
;;; fdex.el ends here
