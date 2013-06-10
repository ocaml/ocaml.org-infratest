ocaml.org-infratest
===================

Regression tests for ocaml.org websites and services.

The first goal of this repository is to gather tests to check that everything
is running fine in OCaml webistes. There is a daily run on a Jenkins instance
that checks the health of services and websites.

As of writing this README, we mostly test forge.ocamlcore.org (one day will
become forge.ocaml.org) and related services.

Initialy this test suite has been designed to handle an OS migration (from lenny
to squeeze). It helps to ensure that after the migration, everything is still
working

TODO: jenkins instances.

What is tested
==============

We test has much things has possible:

* forge.o.o:
  * landing page
  * project test-darcs: read-only access, write access, VCS viewer
  * project test-git: git read-only access, write access, VCS viewer
  * project test-svn: git read-only access, write access, VCS viewer
  * sending email to test-darcs-devel mailing-list
  * homepage test-darcs.forge.ocamlcore.org
  * DNS zonecheck on forge.ocamlcore.org
  * port SMTP, FTP, DNS, HTTP, HTTPS
  * ssh connection to ssh.o.o
* darcs.o.o: VCS viewer, existence of test-darcs project
* git.o.o: VCS viewer, existence of test-git project
* oasis-db:
  * landing page
  * existence of sekred v0.1.5
  * API/list function, existence of project sekred
* planet.o.o:
  * landing page
  * recent update

How to run it
=============

Go to the top of the source directory and run:

$> make

Setting up the test environment
===============================

TODO: generalize HAS_SSH_ACCESS

Setting up a specific user account:

1. Goto forge.ocamlcore.org.
2. Create a user "test-$USER".
3. Enter a valid email.
4. Wait for account creation.
5. TODO: create a ssh-key.
6. Request for your new user to be added to project test-darcs, test-git, test-svn.
7. Wait for effective addition to the projects.
8. Create a file test-ini.sh at the top, with the following content:

TODO
