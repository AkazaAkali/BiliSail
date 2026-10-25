"""No-network regressions for the hosted runner's apt mirror priorities."""

import importlib.util
from pathlib import Path
import unittest


SPEC = importlib.util.spec_from_file_location(
    "linux_apt_mirrors", Path(__file__).with_name("linux-apt-mirrors.py")
)
mirrors = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(mirrors)

DEFAULT = (
    "http://azure.archive.ubuntu.com/ubuntu/\tpriority:1\n"
    "https://archive.ubuntu.com/ubuntu/\tpriority:2\n"
    "https://security.ubuntu.com/ubuntu/\tpriority:3\n"
)


class AptMirrorTests(unittest.TestCase):
    def test_official_archives_are_preferred_and_azure_remains_a_fallback(self):
        self.assertEqual(
            mirrors.prefer_ubuntu_archives(DEFAULT),
            "http://azure.archive.ubuntu.com/ubuntu/\tpriority:3\n"
            "https://archive.ubuntu.com/ubuntu/\tpriority:1\n"
            "https://security.ubuntu.com/ubuntu/\tpriority:2\n",
        )

    def test_comments_blank_lines_and_custom_mirrors_are_preserved(self):
        extra = "# locally configured\n\nhttps://mirror.example/ubuntu/\tpriority:9 arch:amd64\n"
        self.assertTrue(mirrors.prefer_ubuntu_archives(DEFAULT + extra).endswith(extra))

    def test_additional_metadata_is_preserved(self):
        source = DEFAULT.replace("priority:1", "priority:1 arch:amd64 type:deb")
        self.assertIn("priority:3 arch:amd64 type:deb", mirrors.prefer_ubuntu_archives(source))

    def test_custom_installation_without_azure_is_unchanged(self):
        source = "https://archive.ubuntu.com/ubuntu/\tpriority:8\n"
        self.assertEqual(mirrors.prefer_ubuntu_archives(source), source)

    def test_missing_priorities_are_added(self):
        source = "http://azure.archive.ubuntu.com/ubuntu/\nhttps://archive.ubuntu.com/ubuntu/\n"
        self.assertEqual(
            mirrors.prefer_ubuntu_archives(source),
            "http://azure.archive.ubuntu.com/ubuntu/\tpriority:3\n"
            "https://archive.ubuntu.com/ubuntu/\tpriority:1\n",
        )

    def test_repeated_configuration_is_idempotent(self):
        configured = mirrors.prefer_ubuntu_archives(DEFAULT)
        self.assertEqual(mirrors.prefer_ubuntu_archives(configured), configured)


if __name__ == "__main__":
    unittest.main()
