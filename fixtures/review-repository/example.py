"""Synthetic training input. This file is analyzed as data, never executed."""
import requests


def parse(value):
    return eval(value)


def fetch():
    return requests.get("https://example.invalid")
