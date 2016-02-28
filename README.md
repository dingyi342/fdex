[![License GPL 3][badge-license]](http://www.gnu.org/licenses/gpl-3.0.txt)

# fdex
fdex is a file indexing library for indexing folders and files in both continuous or discrete way. This library requires `cl-lib`.



#### To load the library
Put fdex into loadpath and require the package.

```el
(require 'fdex)
```


#### Make a new index
Assume you want to index the folder location
`/home/user/documents/project/helloworld/`,
you need to create a new `fdex` hashtable using `fdex-new`.

```el
(setq directory "/home/user/documents/project/helloworld/")
(setq indextable (fdex-new directory))
```

Now you have `indextable` holding a blank fdex hashtable.
There are two ways to index the files with this blank fdex hashtable.


#### Indexing - in a continuous way
Using `fdex-update`, you can index all folders and files. However, the process is 'blocking' which means Emacs will be freezed if large volume of folder is to be indexed.

```el
(fdex-update indextable)
```


#### Indexing - in a discrete way
Using `fdex-updateRoot` and `fdex-updateNext`, indexing process can be done seperately. In simple terms,
> `fdex-updateRoot` + (`fdex-updateNext` x N) = one complete index cycle

```el
(fdex-updateRoot indextable) ;; => t
(fdex-updateNext indextable) ;; => t
(fdex-updateNext indextable) ;; => t
(fdex-updateNext indextable) ;; => t
;; .......After many times of (fdex-updateNext indextable)
(fdex-updateNext indextable) ;; => nil
;; The returning nil denotes the index cycle has been complete
```

The use of `fdex-updateRoot` and `fdex-updateNext` will become more meaningful if you control how it is invoked.

```el
(defun my-update-control ()
    (unless (fdex-updateNext indextable)
        (fdex-updateRoot indextable)))

(run-with-idle-timer 5 t 'my-update-control)
```


#### To get a list of files
Use `fdex-get-filelist` to get a list of files under indexed path.

```el
(fdex-get-filelist indextable t)
```

#### To get a list of folders
Use `fdex-get-filelist` to get a list of folders under indexed path.

```el
(fdex-get-folderlist indextable t)
```

#### Performance
Testing with my computer with an ssd.
Using `/usr/share/` as the testing folder.
Total: 9254 folders and 175,443 files.
Size: 1.6GB

```el
(setq table (fdex-new "/usr/share/"))

;; Indexing for the first time
(benchmark-run (fdex-update table))
;; ==> (13.129276261 60 3.660709439999991)

;; Indexing for the second time
;; Unless a large portion of files have been changed
;; Even if files have been added or remove
;; Performance should be very similar
(benchmark-run (fdex-update table))
;; ==> (0.382898054 1 0.0698781670000006)

;; Getting file list for the first time
(benchmark-run (fdex-get-filelist table))
;; ==> (3.2519847 4 0.28953332900000106)

;; Getting file list for the second time
;; If no files/folders has been added/removed
;; The cached list is used.
(benchmark-run (fdex-get-filelist table))
;; ==> (1.969e-06 0 0.0)

;; Getting folder list for the first time
(benchmark-run (fdex-get-folderlist table))
;; ==> (0.114238201 0 0.0)

;; Getting folder list for the second time
;; If no files/folders has been added/removed
;; The cached list is used.
(benchmark-run (fdex-get-folderlist table))
;; ==> (5.423e-06 0 0.0)
```

#### Limitation
The number of files (folders) could be indexed is limited.
It is limited by the maximum size of a hash table and the maximum size of a list.
With my computer, I failed to obtain a filelist for indexing `/usr/` which has more than 500k files.

[badge-license]: https://img.shields.io/badge/license-GPL_3-green.svg
