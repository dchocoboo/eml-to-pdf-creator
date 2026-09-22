from __future__ import annotations

import unittest
from unittest.mock import patch

import eml_to_image


class FakeRoute:
    def __init__(self) -> None:
        self.action = None

    def abort(self) -> None:
        self.action = "abort"

    def continue_(self) -> None:
        self.action = "continue"


class FakeRequest:
    def __init__(self, url: str) -> None:
        self.url = url


class FakePage:
    def route(self, _pattern, handler) -> None:
        self.handler = handler


class RemoteResourceTests(unittest.TestCase):
    def test_remote_resource_urls_are_blocked_but_local_content_is_allowed(self) -> None:
        page = FakePage()
        eml_to_image.block_remote_resources(page)

        for url in ("https://example.com/logo.png", "http://example.com/pixel.gif"):
            route = FakeRoute()
            page.handler(route, FakeRequest(url))
            self.assertEqual(route.action, "abort")

        for url in ("file:///tmp/email.html", "data:image/png;base64,AA==", "cid:receipt-logo"):
            route = FakeRoute()
            page.handler(route, FakeRequest(url))
            self.assertEqual(route.action, "continue")

    def test_navigation_timeout_still_renders_pdf(self) -> None:
        events: list[str] = []

        class Page:
            def route(self, _pattern, _handler): pass
            def goto(self, *_args, **_kwargs): raise eml_to_image.PlaywrightTimeoutError("slow")
            def wait_for_load_state(self, *_args, **_kwargs): raise eml_to_image.PlaywrightTimeoutError("slow")
            def evaluate(self, _script): return 200
            def set_viewport_size(self, _size): events.append("viewport")
            def pdf(self, **_kwargs): events.append("pdf")

        class Browser:
            def new_page(self, **_kwargs): return Page()
            def close(self): events.append("close")

        class Playwright:
            class chromium:
                @staticmethod
                def launch(): return Browser()

        class Context:
            def __enter__(self): return Playwright()
            def __exit__(self, *_args): return None

        with patch.object(eml_to_image, "sync_playwright", return_value=Context()):
            eml_to_image.render_to_pdf("<html><body>Receipt</body></html>", "/tmp/pdfmail-timeout-test")

        self.assertEqual(events, ["viewport", "pdf", "close"])


if __name__ == "__main__":
    unittest.main()
