"""Independent bounded readers for the observed unencrypted iOS Pak v11 menu.

This is a format profile, not an Unreal engine or general asset extractor.
Only selected payloads are decoded; virtual names are never disk paths.
"""
from dataclasses import dataclass
import hashlib
from pathlib import PurePosixPath
import struct
import zlib

MAX_RESOURCE = 8 * 1024 * 1024
MAX_INDEX = 32 * 1024 * 1024
MAX_ENTRIES = 100_000
MAX_PAK = 2 * 1024 * 1024 * 1024
PAK_MAGIC = 0x5A6F12E1
FOOTER_BYTES = 221


class MenuImportError(Exception):
    """Unsupported/inconsistent selected data, with a user-facing reason."""


def require(condition, message):
    if not condition:
        raise MenuImportError(message)


class Reader:
    def __init__(self, data, label="data", offset=0):
        self.data, self.label, self.offset = data, label, offset

    def take(self, size):
        require(0 <= size <= len(self.data) - self.offset,
                f"{self.label}: truncated/out-of-range field at {self.offset} ({size} bytes).")
        value = self.data[self.offset:self.offset + size]
        self.offset += size
        return value

    def number(self, code):
        return struct.unpack("<" + code, self.take(struct.calcsize("<" + code)))[0]

    def count(self, maximum=MAX_ENTRIES):
        value = self.number("i")
        require(0 <= value <= maximum, f"{self.label}: count {value} exceeds limit {maximum}.")
        return value

    def boolean(self):
        value = self.number("i")
        require(value in (0, 1), f"{self.label}: invalid serialized Boolean {value}.")
        return bool(value)

    def string(self):
        size = self.number("i")
        require(abs(size) <= 4096, f"{self.label}: string exceeds the 4096-unit limit.")
        if not size:
            return ""
        value = self.take(abs(size) * (1 if size > 0 else 2))
        terminator = b"\0" if size > 0 else b"\0\0"
        require(value.endswith(terminator), f"{self.label}: unterminated string.")
        try:
            return value[:-len(terminator)].decode("utf-8" if size > 0 else "utf-16le")
        except UnicodeError as error:
            raise MenuImportError(f"{self.label}: invalid encoded string.") from error

    def end(self):
        require(self.offset == len(self.data), f"{self.label}: unexpected trailing fields; format variant unsupported.")


def canonical_path(mount, path):
    require(path and "\\" not in path and not path.startswith("/") and
            all(piece not in ("", ".", "..") for piece in path.split("/")), f"Unsafe Pak entry name: {path!r}.")
    require(mount in ("../../../", "../../../Gameface/Content/"), f"Unsupported Pak mount point {mount!r}.")
    value = mount[9:] + path
    prefix = "Gameface/Content/"
    # The same Pak also indexes project/engine/configuration files. Validate
    # their names, but never select or extract them as menu content.
    return value[len(prefix):] if value.startswith(prefix) else None


@dataclass(frozen=True)
class Entry:
    path: str
    canonical: str
    offset: int
    size: int
    compressed: int
    method: str
    method_index: int
    encrypted: bool
    blocks: int


class Pak:
    def __init__(self, archive, info):
        self.archive, self.info = archive, info
        require(not info.flag_bits & 1, f"ZIP member {info.filename} is encrypted; decryption is unsupported.")
        require(info.compress_type in (0, 8), f"ZIP member {info.filename} uses unsupported compression.")
        require(FOOTER_BYTES <= info.file_size <= MAX_PAK, f"Selected Pak size is outside the supported 221-byte to 2-GiB range: {info.filename}.")
        base = max(0, info.file_size - MAX_INDEX)
        # Deflated ZIP members must be streamed through to reach their tail.
        # Discard preceding bytes; never retain or write the whole Pak/IPA.
        with archive.open(info) as stream:
            stream.seek(base)
            tail = stream.read(info.file_size - base + 1)
        require(len(tail) == info.file_size - base, f"Truncated selected Pak {info.filename}.")
        footer = Reader(tail[-FOOTER_BYTES:], info.filename + " footer")
        footer.take(16)  # GUID only; no key lookup or decryption
        require(footer.number("B") == 0, f"{info.filename}: encrypted Pak index unsupported; no keys requested.")
        require(footer.number("I") == PAK_MAGIC, f"{info.filename}: Pak v11 footer magic not found.")
        version = footer.number("I")
        require(version == 11, f"{info.filename}: Pak version {version} unsupported (requires v11).")
        index_offset, index_size, index_sha = footer.number("Q"), footer.number("Q"), footer.take(20)
        methods = []
        for _ in range(5):
            try:
                methods.append(footer.take(32).split(b"\0", 1)[0].decode("ascii"))
            except UnicodeError as error:
                raise MenuImportError(f"{info.filename}: invalid compression method name.") from error
        footer.end()

        def region(offset, size, expected, label):
            require(0 < size <= MAX_INDEX and base <= offset <= info.file_size - FOOTER_BYTES - size,
                    f"{info.filename}: {label} is outside the bounded 32-MiB index tail.")
            data = tail[offset - base:offset - base + size]
            require(hashlib.sha1(data).digest() == expected, f"{info.filename}: {label} SHA1 mismatch; damaged/unsupported archive.")
            return data

        reader = Reader(region(index_offset, index_size, index_sha, "primary index"), info.filename + " primary index")
        mount, count = reader.string(), reader.count()
        reader.number("Q")  # path hash seed
        secondary, directory = {}, None
        for label in ("path hash index", "directory index"):
            if reader.boolean():
                offset, size, sha = reader.number("Q"), reader.number("Q"), reader.take(20)
                data = region(offset, size, sha, label)
                secondary[label] = {"offset": offset, "bytes": size, "sha1": sha.hex()}
                if label == "directory index":
                    directory = data
        require(directory is not None, f"{info.filename}: full directory index required; hash-only Paks unsupported.")
        encoded = reader.take(reader.count(MAX_INDEX))
        require(reader.count() == 0, f"{info.filename}: nonencoded/deleted entry tables unsupported.")
        reader.end()
        dirs, entries, parsed_count = Reader(directory, info.filename + " directory index"), {}, 0
        for _ in range(dirs.count()):
            folder = dirs.string()
            for _ in range(dirs.count()):
                filename, offset = dirs.string(), dirs.number("i")
                require(0 <= offset < len(encoded), f"{info.filename}: deleted/invalid entry offset {offset}.")
                item = Reader(encoded, info.filename + " encoded entry", offset)
                bits = item.number("I")
                if bits & 63 == 63:
                    item.number("I")  # physical header block size is authoritative
                at = item.number("I" if bits & (1 << 31) else "Q")
                size = item.number("I" if bits & (1 << 30) else "Q")
                method = (bits >> 23) & 63
                compressed = item.number("I" if bits & (1 << 29) else "Q") if method else size
                require(method <= len(methods), f"{info.filename}: invalid compression method index {method}.")
                path = folder + filename
                canonical = canonical_path(mount, path)
                parsed_count += 1
                require(parsed_count <= MAX_ENTRIES, f"{info.filename}: excessive directory entries.")
                require(at < index_offset, f"{info.filename}: entry overlaps index: {path}.")
                if canonical is None:
                    continue
                key = canonical.casefold()
                require(key not in entries, f"{info.filename}: duplicate content path {canonical!r}.")
                entries[key] = Entry(path, canonical, at, size, compressed,
                                     methods[method - 1] if method else "stored", method,
                                     bool(bits & (1 << 22)), (bits >> 6) & 65535)
        dirs.end()
        require(parsed_count == count, f"{info.filename}: directory count {parsed_count} differs from declared {count}.")
        self.entries, self.index_offset = entries, index_offset
        self.report = {"member": info.filename, "pakVersion": version, "fileBytes": info.file_size,
                       "zipCRC32": f"{info.CRC:08x}", "mount": mount, "entries": count,
                       "primaryIndex": {"offset": index_offset, "bytes": index_size, "sha1": index_sha.hex()},
                       "secondaryIndexes": secondary}

    def extract(self, selected, decoder):
        result = {}
        with self.archive.open(self.info) as stream:
            for entry in sorted(selected, key=lambda entry: entry.offset):
                label = f"{PurePosixPath(self.info.filename).name}:{entry.path}"
                require(not entry.encrypted, f"{label}: encrypted resource unsupported; no decryption attempted.")
                require(0 < entry.size <= MAX_RESOURCE and 0 < entry.compressed <= MAX_RESOURCE,
                        f"{label}: selected resource exceeds the 8-MiB limit.")
                require(entry.method in ("stored", "Zlib", "Oodle"), f"{label}: compression {entry.method!r} unsupported.")
                require(entry.blocks <= 256, f"{label}: excessive compression block count.")
                header_size = 53 + (4 + 16 * entry.blocks if entry.method_index else 0)
                require(entry.offset + header_size + entry.compressed <= self.index_offset,
                        f"{label}: payload overlaps index or exceeds Pak.")
                stream.seek(entry.offset)
                reader = Reader(stream.read(header_size), label + " physical header")
                physical_offset, compressed, size = reader.number("Q"), reader.number("Q"), reader.number("Q")
                method, sha = reader.number("I"), reader.take(20)
                require(physical_offset == 0 and (compressed, size, method) ==
                        (entry.compressed, entry.size, entry.method_index), f"{label}: physical header disagrees with verified index.")
                blocks = []
                if method:
                    require(reader.count(256) == entry.blocks and entry.blocks > 0,
                            f"{label}: compression block count disagrees with index.")
                    for _ in range(entry.blocks):
                        blocks.append((reader.number("Q"), reader.number("Q")))
                flags, block_size = reader.number("B"), reader.number("I")
                reader.end()
                require(flags == 0, f"{label}: encrypted/deleted/unknown flags {flags:#x} unsupported.")
                previous = header_size
                for start, end in blocks:
                    require(start == previous and start < end <= header_size + compressed,
                            f"{label}: overlapping/padded/out-of-range compression blocks unsupported.")
                    previous = end
                if blocks:
                    require(previous == header_size + compressed and 0 < block_size <= MAX_RESOURCE,
                            f"{label}: compression byte count/output block size invalid.")
                payload = stream.read(compressed)
                require(len(payload) == compressed and hashlib.sha1(payload).digest() == sha,
                        f"{label}: compressed payload SHA1 mismatch or truncated payload.")
                if not blocks:
                    require(method == 0, f"{label}: compressed resource has no block table.")
                    decoded = payload
                else:
                    output = bytearray()
                    for start, end in blocks:
                        expected = min(block_size, size - len(output))
                        require(expected > 0, f"{label}: excessive output blocks.")
                        block = payload[start - header_size:end - header_size]
                        if entry.method == "Oodle":
                            value = decoder.decode(block, expected)
                        else:
                            try:
                                inflater = zlib.decompressobj()
                                value = inflater.decompress(block, expected + 1)
                                require(inflater.eof and not inflater.unused_data and not inflater.unconsumed_tail,
                                        f"{label}: malformed/oversized Zlib block.")
                            except zlib.error as error:
                                raise MenuImportError(f"{label}: Zlib decoding failed: {error}") from error
                        require(len(value) == expected, f"{label}: decoded block differs from {expected} bytes.")
                        output.extend(value)
                    decoded = bytes(output)
                require(len(decoded) == size, f"{label}: decoded resource differs from verified size.")
                report = {"pak": PurePosixPath(self.info.filename).name, "path": entry.canonical,
                          "offset": entry.offset, "compressedBytes": compressed, "decodedBytes": size,
                          "compression": entry.method, "compressedSHA1": sha.hex(),
                          "decodedSHA256": hashlib.sha256(decoded).hexdigest()}
                result[entry.canonical.casefold()] = (decoded, report)
        return result


def texture_png(asset, data):
    require(asset[:4] == bytes.fromhex("c1832a9e"), "Texture .uasset has unsupported package signature.")
    marker = b"PF_B8G8R8A8\0"
    require(data.count(marker) == 1, "Texture is not the supported single PF_B8G8R8A8 image.")
    at = data.index(marker)
    require(at >= 16 and at + 44 <= len(data), "Texture platform data is truncated.")
    width, height, slices, name_size = struct.unpack_from("<4i", data, at - 16)
    require(0 < width <= 2048 and 0 < height <= 2048 and slices == 1 and name_size == 12,
            "Texture dimensions/slices exceed the supported menu format.")
    first, count, cooked, flags, elements, size = struct.unpack_from("<6i", data, at + 12)
    absolute = struct.unpack_from("<q", data, at + 36)[0]
    start = at + 44
    require((first, count, cooked, flags) == (0, 1, 1, 0x48) and elements == size == width * height * 4,
            "Texture requires unsupported mip/bulk format; expected one inline BGRA8 mip.")
    require(absolute == len(asset) + start and start + size + 12 <= len(data),
            "Texture bulk offset/byte count does not match its .uasset/.uexp pair.")
    require(struct.unpack_from("<3i", data, start + size) == (width, height, 1) and
            data[-4:] == bytes.fromhex("c1832a9e"), "Texture mip dimensions/package trailer invalid.")
    pixels = data[start:start + size]
    rgba = bytearray(size)
    rgba[0::4], rgba[1::4], rgba[2::4], rgba[3::4] = pixels[2::4], pixels[1::4], pixels[0::4], pixels[3::4]
    scanlines = b"".join(b"\0" + rgba[y * width * 4:(y + 1) * width * 4] for y in range(height))

    def chunk(tag, value):
        return struct.pack(">I", len(value)) + tag + value + struct.pack(">I", zlib.crc32(tag + value) & 0xffffffff)

    png = (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)) +
           chunk(b"IDAT", zlib.compress(scanlines, 9)) + chunk(b"IEND", b""))
    return png, {"width": width, "height": height, "pixelFormat": "BGRA8 to RGBA8",
                 "sourcePixelSHA256": hashlib.sha256(pixels).hexdigest(),
                 "rgbaSHA256": hashlib.sha256(rgba).hexdigest()}


def font_info(data, expected_name):
    require(len(data) >= 12 and data[:4] in (b"\0\1\0\0", b"OTTO"), "Font is not supported raw TrueType/OpenType SFNT.")
    count = struct.unpack_from(">H", data, 4)[0]
    require(0 < count <= 256 and 12 + 16 * count <= len(data), "Font directory truncated/excessive.")
    tables = {}
    for i in range(count):
        tag, _, offset, size = struct.unpack_from(">4sIII", data, 12 + 16 * i)
        require(tag not in tables and offset <= len(data) - size, "Font has duplicate/out-of-range tables.")
        tables[tag] = data[offset:offset + size]
    names = tables.get(b"name", b"")
    require(len(names) >= 6, "Font has no valid name table.")
    version, records, strings = struct.unpack_from(">HHH", names)
    require(version in (0, 1) and 6 + 12 * records <= strings <= len(names), "Font name records invalid.")
    found = set()
    for i in range(records):
        platform, _, _, name_id, length, offset = struct.unpack_from(">6H", names, 6 + 12 * i)
        require(strings + offset <= len(names) - length, "Font name exceeds table.")
        if name_id == 6 and platform in (0, 1, 3):
            try:
                found.add(names[strings + offset:strings + offset + length].decode("mac_roman" if platform == 1 else "utf-16be"))
            except UnicodeError as error:
                raise MenuImportError("Font PostScript name cannot be decoded.") from error
    require(expected_name in found, f"Font differs from menu contract: expected {expected_name!r}, found {sorted(found)!r}.")
    return {"postScriptName": expected_name, "extension": ".otf" if data[:4] == b"OTTO" else ".ttf"}


def validate_wave(data):
    require(len(data) >= 12 and data[:4] == b"RIFF" and data[8:12] == b"WAVE" and
            struct.unpack_from("<I", data, 4)[0] + 8 == len(data), "Menu sound is not exact RIFF/WAVE.")
    offset, chunks = 12, {}
    while offset < len(data):
        require(offset + 8 <= len(data), "Menu WAV chunk header truncated.")
        tag, size = struct.unpack_from("<4sI", data, offset)
        offset += 8
        require(size <= len(data) - offset and tag not in chunks, "Menu WAV chunk duplicate/out of range.")
        chunks[tag] = data[offset:offset + size]
        offset += size + (size & 1)
    require(offset == len(data), "Menu WAV padding invalid.")
    fmt, samples = chunks.get(b"fmt ", b""), chunks.get(b"data", b"")
    require(len(fmt) >= 22 and samples, "Menu WAV missing format/sample data.")
    tag, channels, rate, _, alignment, bits, extra, frames, coefficients = struct.unpack_from("<HHIIHHHHH", fmt)
    require(tag == 2 and channels == 1 and rate == 22050 and bits == 4 and alignment >= 7 and
            extra == len(fmt) - 18 and 1 <= coefficients <= 32 and len(fmt) >= 22 + 4 * coefficients,
            "Menu WAV requires mono 22050-Hz Microsoft ADPCM and valid coefficients.")
    require(frames == 2 + 2 * (alignment - 7) and len(samples) % alignment == 0, "Menu WAV ADPCM frame/block sizes inconsistent.")
    return {"format": "Microsoft ADPCM", "channels": channels, "sampleRate": rate,
            "blockAlignment": alignment, "framesPerBlock": frames}
