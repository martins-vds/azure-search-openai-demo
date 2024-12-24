#!/bin/sh

. ./scripts/load_python_env.sh

echo 'Running "manageacl.py"'

./.venv/bin/python ./scripts/manageacl.py -v --acl-action enable_acls