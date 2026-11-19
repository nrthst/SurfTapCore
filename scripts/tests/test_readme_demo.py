"""Keep the demo output shown in the README in step with the example program."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
README = ROOT / "README.md"
EXAMPLE = ROOT / "Sources" / "SurfTapExample" / "SurfTapExample.swift"
MARKER = "DEMO ONLY"


def demo_block():
    """Lines of the README code block that shows the offline demo's output."""
    lines = README.read_text(encoding="utf-8").splitlines()
    for index, line in enumerate(lines):
        if line.startswith(MARKER) and index > 0 and lines[index - 1].startswith("```"):
            end = next(i for i in range(index, len(lines)) if lines[i].startswith("```"))
            return lines[index:end]
    return []


def label(line):
    """The fixed text of an output line: everything up to its first value."""
    head, separator, _ = line.partition(": ")
    return head + separator if separator else line


class ReadmeDemoTests(unittest.TestCase):
    def test_readme_shows_the_demo_block(self):
        self.assertGreaterEqual(len(demo_block()), 5)

    def test_every_readme_demo_line_comes_from_the_example(self):
        source = EXAMPLE.read_text(encoding="utf-8")
        for line in demo_block():
            with self.subTest(line=line):
                self.assertIn(label(line), source)

    def test_demo_is_labelled_as_invented_at_both_ends(self):
        block = demo_block()
        self.assertIn("not a forecast", block[0])
        self.assertIn("--live", block[-1])


if __name__ == "__main__":
    unittest.main()
