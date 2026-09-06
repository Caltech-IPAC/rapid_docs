"""Sphinx configuration for the RAPID public documentation site."""

import os

project = "RAPID"
author = "RAPID team"
copyright = "2026, California Institute of Technology"
language = "en"

extensions = [
    "myst_parser",
    "ablog",
    "sphinx_llms_txt",
]

exclude_patterns = [
    "_build",
    ".venv",
    "README.md",
    ".github",
    "scripts",
    "Thumbs.db",
    ".DS_Store",
    "requirements*",
]

# MyST: colon-fence for ABlog's post directive, deflist for reference pages.
myst_enable_extensions = ["colon_fence", "deflist"]
myst_heading_anchors = 3

# ABlog. blog_path points at a generated subpath so ABlog's own archive
# index does not collide with the hand-written log/index.md that
# introduces the section. Atom feeds (one per category) are emitted under
# blog_baseurl, the site origin set below.
# A post declares itself with front matter (blogpost, date, author,
# category). There is no default author: every post names its own.
blog_path = "log/archive"
blog_title = "RAPID log"
blog_feed_archives = True
blog_feed_fulltext = True
blog_authors = {"lead": ("Ben Rusholme", None)}
post_auto_image = 0
# The site origin. Read the Docs exports the canonical URL of the version
# being built (so previews and versions get their own); the production URL
# is the fallback for local builds.
blog_baseurl = os.environ.get(
    "READTHEDOCS_CANONICAL_URL", "https://roman-rapid.readthedocs.io/en/latest/"
)
html_baseurl = blog_baseurl

# pydata-sphinx-theme. Navbar links come from the Home toctree; no navbar_*
# overrides needed.
html_theme = "pydata_sphinx_theme"
# Logo and favicon are the PNG renderings from the project's logo spec; the
# vector sources stay out of this public repository (the mark is a licensed
# stock asset).
html_static_path = ["_static"]
html_logo = "_static/RAPID_logo_1x.png"
html_favicon = "_static/RAPID_icon_tile_256.png"
html_theme_options = {
    "logo": {"text": ""},
    "secondary_sidebar_items": ["page-toc", "sourcelink"],
    "footer_start": ["copyright"],
    "footer_end": [],
    "show_prev_next": False,
    "use_edit_page_button": True,
}
html_context = {
    "github_user": "Caltech-IPAC",
    "github_repo": "rapid_docs",
    "github_version": "main",
    "doc_path": "",
}
html_sidebars = {
    "log/**": [
        "ablog/postcard.html",
        "ablog/recentposts.html",
        "ablog/categories.html",
        "ablog/archives.html",
    ],
}

# sphinx-llms-txt: llms.txt and llms-full.txt at the site root, with
# absolute links under the site origin (html_baseurl).
llms_txt_uri_template = "{base_url}_sources/{docname}{suffix}{sourcelink_suffix}"

# linkcheck
linkcheck_timeout = 30
linkcheck_retries = 2
linkcheck_anchors = True
linkcheck_ignore = []
