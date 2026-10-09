#!/usr/bin/env python3
import base64
import importlib.util
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path

spec = importlib.util.spec_from_file_location("appcast", Path(__file__).with_name("update-appcast.py"))
appcast = importlib.util.module_from_spec(spec)
spec.loader.exec_module(appcast)
FEED = '<rss version="2.0"><channel><title>Marginal</title></channel></rss>'
SIGNATURE = base64.b64encode(bytes(64)).decode()


class FeedTests(unittest.TestCase):
    def feed(self, version="1.2.1", feed=FEED, signature=SIGNATURE, length=1024):
        return appcast.update_feed(feed, version, signature, length, "# Marginal " + version + "\n\n- Install safely <&>\n")

    def test_signed_archive_and_escaped_notes(self):
        item = ET.fromstring(self.feed()).find("channel/item")
        self.assertEqual(item.findtext(f"{{{appcast.SPARKLE}}}version"), "1.2.1")
        self.assertEqual(item.findtext(f"{{{appcast.SPARKLE}}}minimumSystemVersion"), "13.0")
        enclosure = item.find("enclosure")
        self.assertEqual(enclosure.get("url"), "https://github.com/acousland/marginal/releases/download/v1.2.1/Marginal-1.2.1-macOS.zip")
        self.assertEqual(enclosure.get(f"{{{appcast.SPARKLE}}}edSignature"), SIGNATURE)
        self.assertEqual(enclosure.get("length"), "1024")
        self.assertEqual(item.findtext("description"), "<p>Install safely &lt;&amp;&gt;</p>")

    def test_newest_first_retains_history_and_replaces_duplicate(self):
        first = self.feed()
        second = self.feed("1.3.0", first)
        items = ET.fromstring(second).findall("channel/item")
        self.assertEqual([item.findtext(f"{{{appcast.SPARKLE}}}version") for item in items], ["1.3.0", "1.2.1"])
        repeated = self.feed("1.3.0", second)
        self.assertEqual(len(ET.fromstring(repeated).findall("channel/item")), 2)
        with self.assertRaises(ValueError):
            self.feed("1.2.2", second)

    def test_rejects_prereleases_bad_signatures_and_empty_archives(self):
        for version in ["1.2.1-beta", "v1.2.1", "1.2", "1.2.1.0"]:
            with self.assertRaises(ValueError):
                self.feed(version)
        for signature in ["", "***", base64.b64encode(bytes(32)).decode()]:
            with self.assertRaises(ValueError):
                self.feed(signature=signature)
        with self.assertRaises(ValueError):
            self.feed(length=0)
        with self.assertRaises(ValueError):
            self.feed(feed="<rss/>")


if __name__ == "__main__":
    unittest.main()
