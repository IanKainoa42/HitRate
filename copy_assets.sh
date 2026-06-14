#!/bin/bash
ARTIFACTS_DIR="/Users/ianrichardson/.gemini/antigravity/brain/359d5a99-27dc-42bd-953d-a5d3edf43870"
ASSETS_DIR="/Users/ianrichardson/Projects/HitRate/HitRate/Assets.xcassets"

for file in "$ARTIFACTS_DIR"/*.png; do
  if [[ -f "$file" ]]; then
    filename=$(basename -- "$file")
    name="${filename%.*}"
    
    # Strip the timestamp part for a cleaner name (e.g. badge_crown_1781305529168 -> badge_crown)
    # Using bash regex to match _[0-9]{13}$
    clean_name=$(echo "$name" | sed -E 's/_[0-9]{13}$//')
    
    mkdir -p "$ASSETS_DIR/$clean_name.imageset"
    cp "$file" "$ASSETS_DIR/$clean_name.imageset/$filename"
    
    cat << JSON > "$ASSETS_DIR/$clean_name.imageset/Contents.json"
{
  "images" : [
    {
      "filename" : "$filename",
      "idiom" : "universal",
      "scale" : "1x"
    },
    {
      "idiom" : "universal",
      "scale" : "2x"
    },
    {
      "idiom" : "universal",
      "scale" : "3x"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
JSON
  fi
done
