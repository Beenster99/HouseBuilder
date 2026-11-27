"""The asset register and the building catalog reader, shared by every recipe file."""
import json
import os
import re

ASSETS: dict = {}
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))


def register(id: str, fn, label: str, family: str = "", kind: str = "", tags=(), stretch: str = "", **params) -> None:
	"""Add an asset. `id` is category.name.variant; `kind` the building catalog kind (or
	section) it draws; `stretch` the game axis ("y" up, "z" along) a 1 m model is scaled on."""
	if id in ASSETS:
		raise ValueError("duplicate asset id " + id)
	ASSETS[id] = {"id": id, "fn": fn, "label": label, "category": id.split(".")[0], "family": family,
		"kind": kind, "tags": sorted(tags), "stretch": stretch, "params": params}


def asset(id: str, label: str, **kw):
	def deco(fn):
		register(id, fn, label, **kw)
		return fn
	return deco


_catalog = None


def catalog() -> dict:
	"""The building catalog (modules/building/internal/catalog_data.gd) as a dict, so sizes
	have one source of truth."""
	global _catalog
	if _catalog is None:
		src = open(os.path.join(ROOT, "modules/building/internal/catalog_data.gd"), encoding="utf-8").read()
		body = src[src.index("const DATA := {") + len("const DATA := "):]
		body = re.sub(r"#[^\n]*", "", body)
		body = re.sub(r",(\s*[}\]])", r"\1", body)
		_catalog = json.loads(body)
	return _catalog
