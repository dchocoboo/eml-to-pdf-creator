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

    def test_online_success_uses_one_unblocked_page(self) -> None:
        events: list[str] = []

        class Page:
            def __init__(self): self.routes = []
            def route(self, pattern, _handler): self.routes.append(pattern)
            def goto(self, *_args, **kwargs): events.append(("goto", kwargs))
            def evaluate(self, _script): return 200
            def set_viewport_size(self, _size): events.append("viewport")
            def pdf(self, **_kwargs): events.append("pdf")
            def close(self): events.append("page-close")

        class Browser:
            def __init__(self): self.pages = []
            def new_page(self, **_kwargs):
                page = Page()
                self.pages.append(page)
                return page
            def close(self): events.append("close")

        browser = Browser()

        class Playwright:
            class chromium:
                @staticmethod
                def launch(): return browser

        class Context:
            def __enter__(self): return Playwright()
            def __exit__(self, *_args): return None

        with patch.object(eml_to_image, "sync_playwright", return_value=Context()):
            eml_to_image.render_to_pdf("<html><body>Receipt</body></html>", "/tmp/pdfmail-timeout-test")

        self.assertEqual(events[0], ("goto", {"wait_until": "load", "timeout": 15_000}))
        self.assertEqual(events[1:], ["viewport", "pdf", "page-close", "close"])
        self.assertEqual(len(browser.pages), 1)
        self.assertEqual(browser.pages[0].routes, [])

    def test_online_timeout_closes_page_then_renders_blocked_fallback(self) -> None:
        events: list[str] = []

        class Page:
            def __init__(self, timeout_online=False):
                self.timeout_online = timeout_online
                self.routes = []
            def route(self, pattern, _handler): self.routes.append(pattern)
            def goto(self, *_args, **_kwargs):
                if self.timeout_online:
                    raise eml_to_image.PlaywrightTimeoutError("slow")
            def wait_for_load_state(self, *_args, **_kwargs):
                raise eml_to_image.PlaywrightTimeoutError("slow")
            def evaluate(self, _script): return 200
            def set_viewport_size(self, _size): events.append("viewport")
            def pdf(self, **_kwargs): events.append("pdf")
            def close(self): events.append(f"close-{len(events)}")

        class Browser:
            def __init__(self):
                self.pages = [Page(timeout_online=True), Page()]
                self.created = []
            def new_page(self, **_kwargs):
                page = self.pages.pop(0)
                self.created.append(page)
                return page
            def close(self): events.append("browser-close")

        browser = Browser()
        class Playwright:
            class chromium:
                @staticmethod
                def launch(): return browser
        class Context:
            def __enter__(self): return Playwright()
            def __exit__(self, *_args): return None

        with patch.object(eml_to_image, "sync_playwright", return_value=Context()):
            eml_to_image.render_to_pdf("<html><body>Receipt</body></html>", "/tmp/pdfmail-fallback-test")

        self.assertEqual(len(browser.created), 2)
        self.assertEqual(browser.created[0].routes, [])
        self.assertEqual(browser.created[1].routes, ["**/*"])
        self.assertIn("pdf", events)
        self.assertEqual(events[-1], "browser-close")


if __name__ == "__main__":
    unittest.main()
