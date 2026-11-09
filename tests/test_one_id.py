"""No QML object sets `id` twice.

The engine refuses the whole file ("Property value set multiple times"), so
the panel never opens, while qmlformat, qmllint and every suite here pass: none
of them can load the popup outside the shell. It happened once in omarcal (the Picker's
trigger, 2026-10 audit fixes); this catches it from the source.
"""
import glob
import os
import re
import unittest

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
STRING = re.compile(r'"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'')
ID = re.compile(r"(?:^|[{;])\s*id\s*:\s*\w+")


def twice(path):
    found = []
    stack = [[0, 0]]  # per open object: [ids seen, line it opened on]
    with open(path) as src:
        for number, line in enumerate(src, 1):
            code = STRING.sub('""', line).split("//", 1)[0]
            # Walk the line in order, so `Rectangle { id: a; id: b }` on one
            # line is counted against the object it opens.
            for piece in re.split(r"([{}])", code):
                if piece == "{":
                    stack.append([0, number])
                elif piece == "}":
                    if len(stack) > 1:
                        stack.pop()
                else:
                    for _ in ID.finditer(piece if piece.startswith(("{", ";")) else ";" + piece):
                        stack[-1][0] += 1
                        if stack[-1][0] == 2:
                            found.append(f"{os.path.basename(path)}:{number}")
    return found


class OneId(unittest.TestCase):
    def test_no_object_has_two_ids(self):
        found = []
        for path in sorted(glob.glob(os.path.join(ROOT, "*.qml"))):
            found += twice(path)
        self.assertEqual(found, [], "an object sets id twice")


if __name__ == "__main__":
    unittest.main()
