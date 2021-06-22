#!/usr/bin/env sh
# -*- mode: scheme; -*-
exec guile -e main -s "$0" "$@"
!#

;;; A backup script for files and MySQL database
;;; SPDX-FileCopyrightText: Copyright 2021 Stern Data GmbH
;;; SPDX-License-Identifier: MIT

(use-modules (ice-9 binary-ports)
	     (ice-9 format)
	     (ice-9 getopt-long)
	     (ice-9 popen)
	     (ice-9 receive)
	     (srfi srfi-1)
	     (srfi srfi-19))

(define usage "backup.scm OPTIONS

Creates a MySQL dump file and a tarball from source directory, compresses
both files with XZ, places them into the backup directory and prints the
file names on standard output.

MySQL backup relies on socket authentication.

Options:
  -i, --source-dir=DIR       Create tarball from DIR
  -o, --backup-dir=DIR       Write backup files to DIR
  -X, --exclude-from=FILE    Exclude files using patterns from FILE.
                             See tar manual of the same option.
  -u, --mysql-user=USER      Use USER for MySQL authentication (default: root)
  -S, --mysql-socket=SOCKET  Use SOCKET for MySQL connection and authentication
                             (default: /run/mysqld/mysqld.sock)
  -p, --file-prefix=PREFIX   File name prefix (default: \"\")
  -h, --help                 Display this help
")

(define %default-file-prefix "")

(define %default-mysql-user "root")

(define %default-mysql-socket "/run/mysqld/mysqld.sock")

(define options-spec
  '((mysql-user   (single-char #\u)
		  (value #t))
    (mysql-socket (single-char #\S)
		  (value #t))
    (source-dir   (single-char #\i)
		  (value #t))
    (exclude-from (single-char #\X)
		  (value #t))
    (backup-dir   (single-char #\o)
		  (value #t))
    (file-prefix  (single-char #\p)
		  (value #t))
    (help         (single-char #\h)
		  (value #f))))

(define (copy-to-port source sink)
  (let copy-loop ()
    (let ((bytes-read (get-bytevector-n source 8192)))
      (unless (eof-object? bytes-read)
	(put-bytevector sink bytes-read)
	(copy-loop)))))

(define* (backup source-dir backup-dir
		 #:key
		 (file-prefix    %default-file-prefix)
		 (exclude-from   #f)
		 (mysql-user     %default-mysql-user)
		 (mysql-socket   %default-mysql-socket))
  (let* ((timestamp (date->string (current-date) "~4"))
	 (files-tarball (string-append backup-dir
				       "/" file-prefix
				       "files-" timestamp
				       ".tar.xz"))
	 (mysql-dump    (string-append backup-dir
				       "/" file-prefix
				       "mysql-" timestamp
				       ".sql.xz")))
    (unless (stat backup-dir #f)
      (mkdir backup-dir))
    (let* ((exclude-options (if exclude-from
				(list
				 (string-append "--exclude-from="
						exclude-from)) 
				'()))
	   (tar-result (apply system* (append
				       `("tar"
					 "-C" ,source-dir)
				       exclude-options
				       `("-czf"
					 ,files-tarball
					 ".")))))
      (if (eq? tar-result 0)
	  (format #t "~a~%" files-tarball)
	  (begin
	    (format (current-error-port)
		"Error creating files archive: tar failed with exit code ~d~%"
		tar-result)
	    (exit 1))))
    (let ((dump-commands `(("mysqldump"
			    "-S" ,mysql-socket
			    "-u" ,mysql-user
			    "--all-databases")
			   ("xz" "-c")))
	  (success? (lambda (pid)
		      (zero?
		       (status:exit-val (cdr (waitpid pid)))))))
      (receive (from to pids) (pipeline dump-commands)
	(let ((fail-index (list-index (negate success?) (reverse pids))))
	  (call-with-output-file mysql-dump
	    (lambda (dump-out)
	      (copy-to-port from dump-out)))
	  (close to)
	  (close from)
	  (if fail-index
	      (begin
		(format (current-error-port)
			"mysql backup pipeline failed in command: ~a~%"
			(string-join (list-ref dump-commands fail-index)))
		(exit 1))
	      (format #t "~a~%" mysql-dump)))))))

(define (main args)
  (let* ((options      (getopt-long args options-spec))
	 (source-dir   (option-ref options 'source-dir   #f))
	 (backup-dir   (option-ref options 'backup-dir   #f))
	 (exclude-from (option-ref options 'exclude-from #f))
	 (mysql-user   (option-ref options 'mysql-user   %default-mysql-user))
	 (mysql-socket (option-ref options 'mysql-socket %default-mysql-socket))
	 (file-prefix  (option-ref options 'file-prefix  %default-file-prefix))
	 (want-help    (option-ref options 'help         #f)))
    (if want-help
	(begin
	  (display usage)
	  (exit 0)))
    (if (or (not source-dir)
	    (not backup-dir))
	(begin
	  (format (current-error-port)
		  (string-append
		   "Required parameters missing: --source-dir or --backup-dir~%"
		   "See --help for usage~%"))
	  (exit 1)))
    (backup source-dir backup-dir
	    #:file-prefix  file-prefix
	    #:exclude-from exclude-from
	    #:mysql-user   mysql-user
	    #:mysql-socket mysql-socket)))
