# Initial repository checks. Application commands arrive with the first slice.
default:
    @just --list

check:
    python3 scripts/check_docs.py
