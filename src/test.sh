#!/bin/bash

set -e

readonly HAS_SSH_ACCESS=true
readonly HAS_SSH_ADMIN_ACCESS=true
readonly LONG_TEST=true

ERROR_CODE=0

LC_ALL=C
export LC_ALL

readonly fg_green="$(tput setaf 2)"
readonly fg_red="$(tput setaf 1)"
readonly reset="$(tput sgr0)"
readonly MAGIC_NUMBER=$RANDOM
readonly DATE="$(date -R)"
readonly COMMIT_MESSAGE="Automatic test $DATE."

TMP1=$(mktemp)
TMP2=$(mktemp -d)

clean_exit () {
  if [ -e "$TMP1" ]; then
    rm -f "$TMP1" || true
  fi
  if [ -d "$TMP2" ]; then
    rm -rf "$TMP2" || true
  fi
}

trap clean_exit EXIT

logexec () {
  # TODO: redirect to logs.
  "$@" > /dev/null 2>&1
}

ok () {
  echo -e " ${fg_green}OK${reset}"
}

rm -f failure.stamp || true

ko () {
  echo -e " ${fg_red}KO${reset}"
  touch failure.stamp
}

act () {
  if logexec "$@" ; then
    ok
  else
    ko
  fi
}

no_act () {
  if ! logexec "$@" ; then
    ok
  else
    ko
  fi
}

tmp_fetch () {
  echo -n "Retrieving $1 content..."
  act wget -o /dev/null -O "$TMP1" "$1"
}

tmp_contains () {
  PAGE=$1
  shift
  echo -n "$PAGE has '$*'..."
  if grep "$*" "$TMP1" > /dev/null; then
    ok
  else
    ko
  fi
}

tmpdir_enter () {
  rm -rf "$TMP2/tmp" || true
  mkdir "$TMP2/tmp"
  pushd "$TMP2/tmp" > /dev/null
}

tmpdir_leave () {
  popd > /dev/null
  rm -rf "$TMP2/tmp" || true
}

# TODO: mercurial ?
# TODO: grey listing testing
# TODO: news posting (require login)
# TODO: use the soap interface of forge.ocamlcore.org

# Send early so that we can check it at the end.
readonly MAIL_MESSAGE="Test mail of $DATE"
mailx -s "$MAIL_MESSAGE" "test-darcs-devel@lists.forge.ocamlcore.org" <<EOF
This message is a test to check that the mailing list system is working.

Please ignore.
EOF

SCANNED_HOST="none"
tmp_port_scan () {
  SCANNED_HOST="$1"
  logexec nmap -PS -oG "$TMP1" "$SCANNED_HOST"
}

test_port_opened () {
  local PORT="$1"
  echo -n "Port $PORT opened on $SCANNED_HOST..."
  if logexec grep "$PORT/open" "$TMP1"; then
    ok
  else
    ko
  fi
}

test_port_closed () {
  local PORT="$1"
  echo -n "Port $PORT closed on $SCANNED_HOST..."
  if ! logexec grep "$PORT/open" "$TMP1"; then
    ok
  else
    ko
  fi
}

test_max_total_ports () {
  local EXPECTED_NUMBER="$1"
  echo -n "Expecting $EXPECTED_NUMBER ports opened on $SCANNED_HOST..."
  local ACTUAL_NUMBER=$(grep -o , "$TMP1" | wc -l)
  if [ "$EXPECTED_NUMBER" -ge "$ACTUAL_NUMBER" ]; then
    ok
  else
    ko
  fi
}

tmp_port_scan forge.ocamlcore.org
test_port_opened 21 # FTP
test_port_opened 25 # SMTP
test_port_opened 53 # DNS
test_port_opened 80 # HTTP
test_port_opened 443 # HTTPS
test_port_closed 5432 # postgres
test_max_total_ports 9

if $HAS_SSH_ACCESS; then
  echo -n "Connecting to ssh.o.o."
  act ssh ssh.ocamlcore.org true
fi

if $HAS_SSH_ADMIN_ACCESS; then
  echo -n "Connecting to o.o."
  act ssh ocamlcore.org true
fi

# Web tests
tmp_fetch "https://forge.ocamlcore.org"

MAIN_PAGE="http://forge.ocamlcore.org"
if tmp_fetch "$MAIN_PAGE"; then
  tmp_contains $MAIN_PAGE "Top Project Downloads"
  tmp_contains $MAIN_PAGE "Latest News"
fi

# Darcs tests
DARCS_SCM_PAGE="https://forge.ocamlcore.org/scm/?group_id=334"
DARCS_SCM_ANON_REPO="https://forge.ocamlcore.org/anonscm/darcs/test-darcs/test-darcs"
DARCS_SCM_REPO="ssh.ocamlcore.org:/var/lib/gforge/chroot/scmrepos/darcs/test-darcs/test-darcs"
DARCS_VIEWER="http://forge.ocamlcore.org/plugins/scmdarcs/cgi-bin/darcsweb.cgi?r=test-darcs/test-darcs"
if tmp_fetch "$DARCS_SCM_PAGE"; then
  tmp_contains "$DARCS_SCM_PAGE" "darcs get $DARCS_SCM_ANON_REPO"
  tmp_contains "$DARCS_SCM_PAGE" "darcs get $DARCS_SCM_REPO"
  tmp_contains "$DARCS_SCM_PAGE" "Browse Darcs Repository test-darcs"
fi

tmpdir_enter
echo -n "Checkout $DARCS_SCM_ANON_REPO."
act darcs get "$DARCS_SCM_ANON_REPO"
tmpdir_leave

if $HAS_SSH_ACCESS; then
  tmpdir_enter
  echo -n "Checkout $DARCS_SCM_REPO."
  act darcs get "$DARCS_SCM_REPO"
  pushd "test-darcs" > /dev/null
  echo $MAGIC_NUMBER > test.txt
  logexec darcs record -a -m "$COMMIT_MESSAGE"
  echo -n "Push data to $DARCS_SCM_REPO."
  act darcs push -a
  popd > /dev/null
  tmpdir_leave
fi

# Test darcsweb
tmp_fetch "$DARCS_VIEWER"
if $HAS_SSH_ACCESS; then
  tmp_contains "darcs_viewer/default" "$COMMIT_MESSAGE"
fi
tmp_fetch "$DARCS_VIEWER;a=plainblob;f=/test.txt"
if $HAS_SSH_ACCESS; then
  tmp_contains "darcs_viewer/checkout" "$MAGIC_NUMBER"
fi

# Test darcs.o.o.
DARCS_EXTERNAL_VIEWER="http://darcs.ocamlcore.org/cgi-bin/darcsweb.cgi"
tmp_fetch "$DARCS_EXTERNAL_VIEWER"
tmp_contains "test-darcs repository exists" "test-darcs/test-darcs"
tmp_fetch "$DARCS_EXTERNAL_VIEWER?r=test-darcs/test-darcs;a=summary"
if $HAS_SSH_ACCESS; then
  tmp_contains "test-darcs contains last commit." "$COMMIT_MESSAGE"
fi

# Git tests
GIT_SCM_PAGE="https://forge.ocamlcore.org/scm/?group_id=333"
GIT_SCM_ANON_REPO="https://forge.ocamlcore.org/anonscm/git/test-git/test-git.git"
GIT_SCM_SUFFIX="forge.ocamlcore.org/srv/scm/gitroot/test-git/test-git.git"
GIT_SCM_REPO="git+ssh://$GIT_SCM_SUFFIX"
GIT_VIEWER="http://forge.ocamlcore.org/plugins/scmgit/cgi-bin/gitweb.cgi?p=test-git/test-git.git"
if tmp_fetch "$GIT_SCM_PAGE"; then
  tmp_contains "$GIT_SCM_PAGE" "git clone $GIT_SCM_ANON_REPO"
  tmp_contains "$GIT_SCM_PAGE" "git clone git+ssh://"
  tmp_contains "$GIT_SCM_PAGE" "$GIT_SCM_SUFFIX"
fi

tmpdir_enter
echo -n "Checkout $GIT_SCM_ANON_REPO."
act git clone "$GIT_SCM_ANON_REPO"
tmpdir_leave

if $HAS_SSH_ACCESS; then
  tmpdir_enter
  echo -n "Checkout $GIT_SCM_REPO."
  act git clone "$GIT_SCM_REPO"
  pushd "test-git" > /dev/null
  echo $MAGIC_NUMBER > test.txt
  logexec git add test.txt || true
  logexec git commit -am "$COMMIT_MESSAGE"
  echo -n "Push data to $GIT_SCM_REPO."
  act git push origin master
  popd > /dev/null
  tmpdir_leave
fi

# Test gitweb
tmp_fetch "$GIT_VIEWER;a=blob_plain;f=test.txt;hb=HEAD"
if $HAS_SSH_ACCESS; then
  tmp_contains "git_viewer/checkout" "$MAGIC_NUMBER"
fi
tmp_fetch "$GIT_VIEWER;a=summary"
if $HAS_SSH_ACCESS; then
  tmp_contains "git_viewer/default" "$COMMIT_MESSAGE"
fi

# Test git.o.o.
GIT_EXTERNAL_VIEWER="http://git.ocamlcore.org/cgi-bin/gitweb.cgi"
tmp_fetch "$GIT_EXTERNAL_VIEWER"
tmp_contains "test-git repository exists" "test-git/test-git.git"
tmp_fetch "$GIT_EXTERNAL_VIEWER?p=test-git/test-git.git;a=summary"
if $HAS_SSH_ACCESS; then
  tmp_contains "test-git contains last commit." "$COMMIT_MESSAGE"
fi

# SVN tests
SVN_SCM_PAGE="https://forge.ocamlcore.org/scm/?group_id=332"
# TODO: make it the same as git and darcs for consistency (need to work on the
# forge settings).
SVN_SCM_ANON_REPO="svn://scm.ocamlcore.org/svn/test-svn/trunk"
SVN_SCM_SUFFIX="scm.ocamlcore.org/svn/test-svn/trunk"
SVN_SCM_REPO="svn+ssh://$SVN_SCM_SUFFIX"
SVN_VIEWER="http://forge.ocamlcore.org/scm/viewvc.php"
if tmp_fetch "$SVN_SCM_PAGE"; then
  tmp_contains "$SVN_SCM_PAGE" "svn checkout $SVN_SCM_ANON_REPO"
  tmp_contains "$SVN_SCM_PAGE" "svn checkout svn+ssh://"
  tmp_contains "$SVN_SCM_PAGE" "$SVN_SCM_SUFFIX"
fi

tmpdir_enter
echo -n "Checkout $SVN_SCM_ANON_REPO."
act svn checkout "$SVN_SCM_ANON_REPO"
tmpdir_leave

if $HAS_SSH_ACCESS; then
  tmpdir_enter
  echo -n "Checkout $SVN_SCM_REPO."
  act svn checkout "$SVN_SCM_REPO"
  pushd "trunk" > /dev/null
  echo $MAGIC_NUMBER > test.txt
  logexec svn add test.txt || true
  echo -n "Push data to $SVN_SCM_REPO."
  act svn commit -m "$COMMIT_MESSAGE"
  popd > /dev/null
  tmpdir_leave

  # Test viewvc
  tmp_fetch "$SVN_VIEWER/*checkout*/trunk/test.txt?root=test-svn"
  tmp_contains "svn_viewer/checkout" "$MAGIC_NUMBER"
  tmp_fetch "$SVN_VIEWER/trunk/?root=test-svn"
  tmp_contains "svn_viewer/default" "$COMMIT_MESSAGE"
fi

# Planet tests.
tmp_fetch "http://planet.ocaml.org/"
TODAY="$(date +"%B %d, %Y")"
tmp_contains "planet has been updated" "$TODAY"

# test-darcs homepage.
tmp_fetch "http://test-darcs.forge.ocamlcore.org/"
tmp_contains "content of the homepage of test-darcs" \
  "This project is a test for the OCaml Forge infrastructure."

# oasis.o.o tests.
OASIS_DB_ROOT="http://oasis.ocamlcore.org/dev"
tmp_fetch "$OASIS_DB_ROOT/home"
tmp_contains "OASIS-DB test1" "the comprehensive OCaml package archive"

tmp_fetch "$OASIS_DB_ROOT/view/sekred/0.1.5"
tmp_contains "sekred: Password manager for automatic installation."

tmp_fetch "$OASIS_DB_ROOT/api/0.1/sexp/pkg/list"
tmp_contains "sekred is listed" "sekred"


# Robots presence
tmp_fetch "http://forge.ocamlcore.org/robots.txt"
tmp_contains "robots content of forge.o.o" "Disallow: /softwaremap/"

tmp_fetch "https://forge.ocamlcore.org/robots.txt"
tmp_contains "robots content of forge.o.o" "Disallow: /softwaremap/"

tmp_fetch "http://darcs.ocamlcore.org/robots.txt"
tmp_contains "robots content of darcs.o.o" 'Disallow: /repos/\*/_darcs'

tmp_fetch "http://git.ocamlcore.org/robots.txt"
tmp_contains "robots content of git.o.o" "Disallow:"


# TODO: test upload REST interface.

# DNS tests.
if $LONG_TEST; then
  echo -n "Running zonecheck..."
  act zonecheck -4 forge.ocamlcore.org
fi

# This test must be the last one, so that we have higher chance that the mail
# sent at the beginning is received.
WAITING=0
ML_DATE="$(date +%Y-%B)"
ML_ARCHIVE_PAGE="https://lists.forge.ocamlcore.org/pipermail/test-darcs-devel/$ML_DATE/thread.html"
ATTEMPTS=12
FOUND=false
while [ $ATTEMPTS -gt 0 ] && ! $FOUND ; do
  echo "Retrieving test-darcs-devel/$ML_DATE archive content..."
  logexec wget -o /dev/null --no-check-certificate -O "$TMP1" "$ML_ARCHIVE_PAGE"
  echo "$ML_ARCHIVE_PAGE has '$MAIL_MESSAGE'..."
  if logexec grep "$MAIL_MESSAGE" "$TMP1"; then
    FOUND=true
  else
    sleep 5
    ATTEMPTS=$(($ATTEMPTS - 1))
  fi
done
echo -n "Mail sent to mailing-list received..."
if $FOUND; then
  ok
else
  ko
fi

# Define the exit code.
if [ -e failure.stamp ]; then
  echo "Some failures exist."
  exit 1
fi
