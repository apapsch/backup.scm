# A backup script for files and MySQL database

## Usage

```
backup.scm OPTIONS

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
```

## MySQL backup

MySQL backup relies on socket authentication, for which a MySQL user
and corresponding UNIX user is needed. Socket authentication plugin is
called [`unix_socket` in MariaDB](socket-auth-mariadb) and
[`auth_socket` in MySQL](socket-auth-mysql).

You should grant only the privileges necessary to do the backup. From
[mysqldump docs](mysqldump-docs):

    mysqldump requires at least the SELECT privilege for dumped tables,
	SHOW VIEW for dumped views, TRIGGER for dumped triggers, LOCK TABLES
	if the --single-transaction option is not used, and (as of MySQL 8.0.21)
	PROCESS if the --no-tablespaces option is not used. Certain options
	might require other privileges as noted in the option descriptions.

Grant the privileges on the databases you want to appear in the dump
file.

```
CREATE USER 'backup'@'localhost' IDENTIFIED WITH unix_socket;
GRANT SELECT,SHOW VIEW,TRIGGER,LOCK TABLES ON foo.* TO 'backup'@'localhost';
FLUSH PRIVILEGES;
```

## Integration into Guix

In your operating system config, you could add this script as a `local-file`,
which is then executed via `mcron`. Note `#:recursive #t` which preserves
the permission bits on `backup.scm`.

```
(define backup-script
  (local-file "backup.scm/backup.scm"
	      #:recursive? #t))

(define backup-job
  #~(job '(next-hour '(0))
	     (lambda ()
	       (execl #$backup-script #$backup-script))))

(operating-system
  (services
    (append (list (simple-service 'backup-jobs
                                  mcron-service-type
                                  (list backup-job)))
            %base-services)))
```

[socket-auth-mariadb](https://mariadb.com/kb/en/authentication-plugin-unix-socket/)
[socket-auth-mysql](https://dev.mysql.com/doc/refman/8.0/en/socket-pluggable-authentication.html)
[mysqldump-docs](https://dev.mysql.com/doc/refman/8.0/en/mysqldump.html)
