[![License GPL 3][badge-license]](http://www.gnu.org/licenses/gpl-3.0.txt)

# fdex
fdex is a file indexing library for indexing folders and files in both continuous or discrete way. This library requires `cl-lib`.



##### To load the library
Put fdex into loadpath and require the package.

```el
(require 'fdex)
```


##### Make a new index
Assume you want to index the folder location
`/home/user/documents/project/helloworld/`,
you need to create a new `fdex` hashtable using `fdex-new`.

```el
(setq directory "/home/user/documents/project/helloworld/")
(setq indextable (fdex-new directory))
```

Now you have `indextable` holding a blank fdex hashtable.
There are two ways to index the files with this blank fdex hashtable.


##### Indexing - in a continuous way
Using `fdex-update`, you can index all folders and files. However, the process is 'blocking' which means Emacs will be freezed if large volume of folder is to be indexed.

```el
(fdex-update indextable)
```


##### Indexing - in a discrete way
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

The use of `fdex-updateRoot` and `fdex-updateNext` will become more meaning if you control how it is invoked.

```el
(defun my-update-control ()
    (unless (fdex-updateNext indextable)
        (fdex-updateRoot indextable)))

(run-with-idle-timer 5 t 'my-update-control)
```


##### To get a list of files
Use `fdex-get-filelist` to get a list of files under indexed path.

```el
(fdex-get-filelist indextable t)
```


[badge-license]: https://img.shields.io/badge/license-GPL_3-green.svg
