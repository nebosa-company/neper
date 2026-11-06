# Script-side regression cases

Self-written `.html` cases for the script-side browser stream, kept in the tree so a fix has a
regression test that does not depend on the WPT corpus staying put.

They use the WPT `testharness`, which is not vendored here. `web-run ROOT LIST` serves each path in
LIST relative to ROOT, so ROOT has to be a directory that holds both `resources/testharness*.js` and
the case itself. Copy the case next to a checkout's `resources/` (or stage a small root), then:

```
mkdir -p tmp/wr/resources tmp/wr/cases
cp D:/data/wpt-script/resources/testharness2*.js tmp/wr/resources/
cp tests/browser/web/cases/<case>.html tmp/wr/cases/
echo cases/<case>.html > tmp/wr/list.txt
build/windows/web-run.exe tmp/wr tmp/wr/list.txt --show
```

`list.txt` in this directory lists the cases; it is the file to extend when a script-side fix lands.

Adding a case means it must **fail on the build before the fix** and pass after — check both, since a
case that passes either way is not a regression test.
