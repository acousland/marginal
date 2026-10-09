#!/usr/bin/env python3
"""Read Marginal's feed on stdin and add a signed, stable release to stdout."""
import argparse
import base64
import email.utils
import html
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

SPARKLE = "http://www.andymatuschak.org/xml-namespaces/sparkle"
ET.register_namespace("sparkle", SPARKLE)


def update_feed(feed, version, signature, length, notes):
    if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", version):
        raise ValueError("version must be major.minor.patch")
    if len(base64.b64decode(signature, validate=True)) != 64 or length <= 0:
        raise ValueError("a valid Ed25519 signature and positive archive size are required")
    tree = ET.ElementTree(ET.fromstring(feed))
    channel = tree.getroot().find("channel")
    if tree.getroot().tag != "rss" or channel is None:
        raise ValueError("feed must have an RSS channel")
    numeric_version = tuple(map(int, version.split(".")))
    for old in channel.findall("item"):
        old_version = old.findtext(f"{{{SPARKLE}}}version", "")
        if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", old_version):
            raise ValueError("existing release has an invalid build version")
        if tuple(map(int, old_version.split("."))) > numeric_version:
            raise ValueError("new version must not be older than the feed")
        if old_version == version:
            channel.remove(old)
    item = ET.Element("item")
    ET.SubElement(item, "title").text = f"Marginal {version}"
    ET.SubElement(item, "pubDate").text = email.utils.formatdate(usegmt=True)
    ET.SubElement(item, f"{{{SPARKLE}}}version").text = version
    ET.SubElement(item, f"{{{SPARKLE}}}shortVersionString").text = version
    ET.SubElement(item, f"{{{SPARKLE}}}minimumSystemVersion").text = "13.0"
    # Plain paragraphs keep the release notes safe and readable in Sparkle's HTML view.
    ET.SubElement(item, "description").text = "".join(
        f"<p>{html.escape(line.removeprefix('- '))}</p>"
        for line in notes.splitlines() if line.strip() and not line.startswith("# ")
    )
    ET.SubElement(item, "enclosure", {
        "url": f"https://github.com/acousland/marginal/releases/download/v{version}/Marginal-{version}-macOS.zip",
        f"{{{SPARKLE}}}edSignature": signature,
        "length": str(length), "type": "application/octet-stream",
    })
    first_item = channel.find("item")
    channel.insert(list(channel).index(first_item) if first_item is not None else len(channel), item)
    for old in channel.findall("item")[20:]:
        channel.remove(old)
    ET.indent(tree, space="  ")
    return '<?xml version="1.0" encoding="utf-8"?>\n' + ET.tostring(tree.getroot(), encoding="unicode") + "\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", required=True)
    parser.add_argument("--signature", required=True)
    parser.add_argument("--length", type=int, required=True)
    parser.add_argument("--notes", type=Path, required=True)
    args = parser.parse_args()
    if not args.notes.read_text().splitlines()[0].startswith(f"# Marginal {args.version}"):
        parser.error("release notes must start with the requested version")
    print(update_feed(sys.stdin.read(), args.version, args.signature, args.length, args.notes.read_text()), end="")


if __name__ == "__main__":
    main()
