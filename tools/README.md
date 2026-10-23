# Repository tools

`python tools/check_docs.py --report` lists path-shaped references in Markdown that
do not exist. Use `--strict` to fail on findings or `--selftest` to check the
parser. Intentional future paths can go in `tools/docs_check_allow.txt`.
