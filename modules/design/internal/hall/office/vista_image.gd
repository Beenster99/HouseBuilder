extends RefCounted
## Turns any picture a player picks into the design office's vista: an equirectangular
## panorama the hall's sky draws, so it shows through the window wall from every angle.
## A picture already about 2:1 is taken as a full 360 degree panorama. Any other photo is laid
## across the view out of the window (its middle straight ahead, -Z), mirrored round the back
## so the seams meet, with its top and bottom edges carried up into the sky and down to the
## ground. Everything here is Image calls (no per-pixel loops), so it is quick enough to run on
## a worker thread.

## The panorama's size, px (2:1).
const WIDTH := 4096
## The smaller size tried when the larger one would not fit in one message.
const SMALL_WIDTH := 3072
## How many degrees of the view, top to bottom, an ordinary photo fills.
const PHOTO_SPAN_DEG := 75.0
## How far down an ordinary photo its horizon sits (share of its height).
const PHOTO_HORIZON := 0.55
## The most bytes a vista may be when shared (one reliable message to each player).
const MAX_BYTES := 1_400_000
## Picture files a player can pick or drop.
const EXTENSIONS := ["png", "jpg", "jpeg", "webp", "bmp", "tga"]


static func is_picture(path: String) -> bool:
	return path.get_extension().to_lower() in EXTENSIONS


## True when the picture is close enough to 2:1 to wrap all the way round.
static func is_panorama(img: Image) -> bool:
	var aspect := float(img.get_width()) / maxf(1.0, float(img.get_height()))
	return aspect >= 1.85 and aspect <= 2.15


## The 2:1 panorama for a picture (a new Image, RGB8).
static func to_panorama(src: Image, width := WIDTH) -> Image:
	var img := src.duplicate() as Image
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGB8)
	var h := width / 2
	if is_panorama(img):
		img.resize(width, h, Image.INTERPOLATE_LANCZOS)
		return img
	var out := Image.create_empty(width, h, false, Image.FORMAT_RGB8)
	# The photo's size in the panorama: PHOTO_SPAN_DEG tall, as wide as its shape says, at most
	# all the way round.
	var ph := int(round(h * PHOTO_SPAN_DEG / 180.0))
	var pw := int(round(ph * float(img.get_width()) / float(img.get_height())))
	if pw > width:
		ph = int(round(ph * float(width) / float(pw)))
		pw = width
	img.resize(maxi(pw, 1), maxi(ph, 1), Image.INTERPOLATE_LANCZOS)
	var flipped := img.duplicate() as Image
	flipped.flip_x()
	var top := int(round(h * 0.5 - ph * PHOTO_HORIZON))
	top = clampi(top, 0, h - ph)
	# The photo straight ahead, then mirrored copies out to both sides until the ring is full.
	var cx := width / 2 - pw / 2
	var reach := int(ceil(float(width) / float(pw))) + 1
	for k in range(-reach, reach + 1):
		var piece := img if posmod(k, 2) == 0 else flipped
		out.blit_rect(piece, Rect2i(Vector2i.ZERO, Vector2i(pw, ph)), Vector2i(cx + k * pw, top))
	_extend(out, top, true)
	_extend(out, top + ph, false)
	return out


## Fills the panorama above `edge` (sky, up = true) or from `edge` down (ground) with each
## column's colour at the photo's edge, softened, fading toward the edge's average colour (and
## a little deeper toward the zenith and the nadir).
static func _extend(out: Image, edge: int, up: bool) -> void:
	var w := out.get_width()
	var h := out.get_height()
	var rows := edge if up else h - edge
	if rows <= 0:
		return
	var row_y := clampi(edge if up else edge - 1, 0, h - 1)
	var line := out.get_region(Rect2i(0, row_y, w, 1))
	line.resize(maxi(1, w / 64), 1, Image.INTERPOLATE_BILINEAR)
	var avg := Color(0, 0, 0)
	for x in line.get_width():
		avg += line.get_pixel(x, 0)
	avg /= float(line.get_width())
	line.resize(w, 1, Image.INTERPOLATE_BILINEAR)
	var fill := line.duplicate() as Image
	fill.resize(w, rows, Image.INTERPOLATE_NEAREST)
	# The fade: a column of the average colour whose alpha grows away from the photo.
	var far := avg.darkened(0.35) if not up else avg.lerp(Color(0.18, 0.3, 0.55), 0.35)
	var ramp := Image.create_empty(1, rows, false, Image.FORMAT_RGBA8)
	for y in rows:
		var t := float(rows - y) / float(rows) if up else float(y + 1) / float(rows)
		var c := avg.lerp(far, t * t)
		c.a = clampf(t * 1.6, 0.0, 1.0)
		ramp.set_pixel(0, y, c)
	ramp.resize(w, rows, Image.INTERPOLATE_NEAREST)
	fill.convert(Image.FORMAT_RGBA8)
	fill.blend_rect(ramp, Rect2i(0, 0, w, rows), Vector2i.ZERO)
	fill.convert(Image.FORMAT_RGB8)
	out.blit_rect(fill, Rect2i(0, 0, w, rows), Vector2i(0, 0 if up else edge))


## The panorama as WebP bytes small enough to share, or empty if it can't be made so.
static func encode(pano: Image) -> PackedByteArray:
	var bytes := pano.save_webp_to_buffer(true, 0.82)
	if bytes.size() > MAX_BYTES and pano.get_width() > SMALL_WIDTH:
		var small := pano.duplicate() as Image
		small.resize(SMALL_WIDTH, SMALL_WIDTH / 2, Image.INTERPOLATE_BILINEAR)
		bytes = small.save_webp_to_buffer(true, 0.75)
	if bytes.size() > MAX_BYTES:
		bytes = pano.save_webp_to_buffer(true, 0.5)
	return bytes if bytes.size() <= MAX_BYTES else PackedByteArray()


## A picture file straight to shareable bytes ("" error on success): {bytes, error}.
static func from_file(path: String) -> Dictionary:
	if not is_picture(path):
		return {"bytes": PackedByteArray(), "error": "That isn't a picture (png, jpg or webp)."}
	var img := Image.load_from_file(path)
	if img == null or img.is_empty():
		return {"bytes": PackedByteArray(), "error": "Couldn't read that picture."}
	var bytes := encode(to_panorama(img))
	if bytes.is_empty():
		return {"bytes": bytes, "error": "That picture is too detailed to share; try a smaller one."}
	return {"bytes": bytes, "error": ""}


## Shared bytes back to a texture for the sky (null if they don't decode).
static func texture_from(bytes: PackedByteArray) -> Texture2D:
	var img := Image.new()
	if bytes.is_empty() or img.load_webp_from_buffer(bytes) != OK or img.is_empty():
		return null
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)
