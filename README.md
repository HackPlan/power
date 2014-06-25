# Power

Zero-configuration static web server for Mac OS X

### How to install

To install or upgrade Power, open a terminal and run this command:

```
$ curl power.hackplan.com/install.sh | sh
```

### How to use

To set up a static web app, just symlink it into ~/.power:

```
$ cd ~/.power
$ ln -s /path/to/myapp
```

That’s it! Your app will be up and running at http://myapp.dev/.

### How to uninstall

To uninstall or upgrade Power, just run this command:

```
$ curl power.hackplan.com/uninstall.sh | sh
```