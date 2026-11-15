#!/usr/bin/env python3
"""Prepare archived particle TXD sprites as an ignored native texture atlas."""
import hashlib
import json
import math
from PIL import Image
from prepare_native_models import GAME, textures

def main():
    images = {}
    source = {}
    for name in ('particle','effectspc'):
        path = GAME / (name+'.txd')
        source[path.name] = hashlib.sha256(path.read_bytes()).hexdigest()
        images.update(textures(path))
    names = sorted(images)
    atlas = Image.new('RGBA',(2048,math.ceil(len(names)/16)*128))
    for index,name in enumerate(names):
        atlas.paste(images[name].resize((128,128),Image.Resampling.LANCZOS),((index%16)*128,(index//16)*128))
    folder = GAME/'native/effects';folder.mkdir(parents=True,exist_ok=True)
    atlas.save(folder/'atlas.png')
    # The water renderer repeats the original unresized texture, with mipmaps.
    if 'waterclear256' in images: images['waterclear256'].save(folder/'waterclear256.png')
    (folder/'index.json').write_text(json.dumps({'sprites':{n:i for i,n in enumerate(names)},'source':source},separators=(',',':')))
    print(f'Prepared {len(names)} archived particle sprites under local-only/')

if __name__ == '__main__': main()
