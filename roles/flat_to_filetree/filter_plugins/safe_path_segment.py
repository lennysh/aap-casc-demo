#!/usr/bin/python
# -*- coding: utf-8 -*-

from __future__ import absolute_import, division, print_function

__metaclass__ = type

import re

DOCUMENTATION = r"""
    name: safe_path_segment
    author: Lenny Shirley II
    short_description: Sanitize a string for use as a filesystem path segment or filename
    description:
      - Replaces path separators and other filesystem-unsafe characters with underscores.
      - Preserves spaces, hyphens, and other readable characters where the OS allows them.
    options:
      _input:
        description: String to sanitize.
        type: str
        required: true
"""

# Path separators plus characters unsafe on common filesystems (notably Windows).
_UNSAFE_SEGMENT_RE = re.compile(r'[/\\:\0*?"<>|]|[\x00-\x1f]')
_CONSECUTIVE_UNDERSCORES_RE = re.compile(r"_+")


def safe_path_segment(value):
    """Return a filesystem-safe path segment or filename."""
    if value is None:
        return "unnamed"

    result = str(value).strip()
    result = _UNSAFE_SEGMENT_RE.sub("_", result)
    result = _CONSECUTIVE_UNDERSCORES_RE.sub("_", result)
    result = result.strip(" _.")

    return result or "unnamed"


class FilterModule(object):
    """Ansible filter plugin for safe filesystem path segments."""

    def filters(self):
        return {
            "safe_path_segment": safe_path_segment,
        }
