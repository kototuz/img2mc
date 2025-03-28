package main

import "core:fmt"
import "core:os"
import "core:strings"
import "core:slice"
import "core:image/png"
import "core:image"

//import rl "vendor:raylib"

import "json"

BlockFacing :: struct {
    name: string,
    kind: BlockFacingKind,
}

BlockFacingKind :: enum {
    TOP  = 0b01,
    SIDE = 0b10,
    ALL  = 0b11,
}

BLOCK_FACINGS :: [?]BlockFacing{
    {name="",            kind=.ALL},
    {name="axis=y",      kind=.TOP},
    {name="axis=x",      kind=.SIDE},
    {name="facing=up",   kind=.TOP},
    {name="facing=east", kind=.SIDE},
}

OUTPUT_FILE        :: "../blocks.odin"

BLOCK_STATES_DIR   :: "block_states/"
BLOCK_MODELS_DIR   :: "block_models/"
BLOCK_TEXTURES_DIR :: "block_textures/"

path_builder: strings.Builder
output_file:  os.Handle
textures:     [dynamic]string

log :: proc(format: string, args: ..any) {
    fmt.printfln(format, ..args)
}

json_find_model :: proc(root: json.Value) -> (res: json.Object) {
    #partial switch v in root {
    case json.Object:
        model, ok := v["model"]
        if ok {
            return v
        }

        for _, val in v {
            res = json_find_model(val)
            if res != nil {
                return
            }
        }

    case json.Array:
        for el in v {
            res = json_find_model(el)
            if res != nil {
                return
            }
        }
    }

    return nil
}

load_json_from_file_path :: proc(file_path: string) -> (json.Value, bool) {
    bytes, err := os.read_entire_file_from_filename_or_err(file_path, context.allocator)
    if err != nil {
        fmt.eprintfln("[ERROR] Could not read data from file '%v': %v", file_path, os.error_string(err))
        return nil, false
    }
    defer delete(bytes)

    json, jerr := json.parse(bytes)
    if jerr != nil {
        fmt.eprintfln("[ERROR] Could not parse json in file '%v': %v", file_path, jerr)
        return nil, false
    }

    return json, true
}

append_texture :: proc(texture: string, state: string) {
    if slice.contains(textures[:], texture) {
        log("[INFO] Texture '%v' skipped: already exists", texture)
        return
    }

    strings.builder_reset(&path_builder)
    strings.write_string(&path_builder, "generator/")
    strings.write_string(&path_builder, BLOCK_TEXTURES_DIR)
    strings.write_string(&path_builder, texture[16:])
    strings.write_string(&path_builder, ".png")

    assert(os.exists(string(path_builder.buf[10:])))
    fmt.fprintfln(output_file, "    {{path=`%v`}},", strings.to_string(path_builder))

    append(&textures, texture)
}

parse_model :: proc(block_name: string, facing_idx: int, model_name: string) -> bool {
    strings.builder_reset(&path_builder)
    strings.write_string(&path_builder, BLOCK_MODELS_DIR)
    strings.write_string(&path_builder, model_name[16:])
    strings.write_string(&path_builder, ".json")

    if !os.exists(strings.to_string(path_builder)) {
        log("[INFO] Model '%v' was skipped: could not find model file", model_name)
        return true
    }

    json_data := load_json_from_file_path(strings.to_string(path_builder)) or_return
    defer json.destroy_value(json_data)

    parent, ok := json_data.(json.Object)["parent"]
    if !ok {
        log("[INFO] Model '%v' was skipped: could not find parent field", model_name)
        return true
    }

    switch parent.(json.String) {
    case "minecraft:block/cube_all":
        texture := json_data.(json.Object)["textures"].(json.Object)["all"]
        append_texture(texture.(json.String), "")
    }

    return true
}

main :: proc() {
    // Open the block states directory

    dir, err := os.open(BLOCK_STATES_DIR)
    if err != nil {
        fmt.eprintfln("[ERROR] Could not open dir '%v': %v", BLOCK_STATES_DIR, os.error_string(err))
        return
    }

    // Initialize some stuff

    path_builder = strings.builder_make()
    defer strings.builder_destroy(&path_builder)

    textures = make([dynamic]string)
    defer delete(textures)

    output_file, err = os.open(OUTPUT_FILE, os.O_WRONLY | os.O_CREATE | os.O_TRUNC, os.S_IWUSR | os.S_IRUSR)
    if err != nil {
        fmt.eprintfln("[ERROR] Could not open file '%v': %v", OUTPUT_FILE, os.error_string(err))
        return
    }
    defer os.close(output_file)

    // Parse each block state

    fis: []os.File_Info
    fis, err = os.read_dir(dir, -1)
    if err != nil {
        fmt.eprintfln("[ERROR] Could not read dir '%v': %v", BLOCK_STATES_DIR, os.error_string(err))
        return
    }
    defer os.file_info_slice_delete(fis)

    fmt.fprintln(output_file,
`package main
import rl "vendor:raylib"

Block :: struct {
    name_with_state: string,
    average_color:   rl.Color,
}

blocks := [?]Block {`)

    for fi in fis {
        // Read the block state file
        json_data := load_json_from_file_path(fi.fullpath) or_break
        defer json.destroy_value(json_data)

        // Expect that the file contains 'variants' field
        variants, ok := json_data.(json.Object)["variants"]
        if !ok {
            log("[INFO] Block state '%v' was skipped: could not find 'variants' field", fi.name)
            continue
        }

        // Iterate over blockstate variants
        model: json.Object
        block_name := strings.trim_suffix(fi.name, ".json")
        loop: for k, v in variants.(json.Object) {
            model = json_find_model(v)
            assert(model != nil)
            
            model_name := model["model"].(json.String)
            model_x := model["x"].(json.Float) or_else 0

            strings.builder_reset(&path_builder)
            strings.write_string(&path_builder, BLOCK_MODELS_DIR)
            strings.write_string(&path_builder, model_name[16:])
            strings.write_string(&path_builder, ".json")

            if !os.exists(strings.to_string(path_builder)) {
                log("[INFO] Model '%v' was skipped: could not find model file", model_name)
                continue
            }

            json_data := load_json_from_file_path(strings.to_string(path_builder)) or_break
            defer json.destroy_value(json_data)

            parent, ok := json_data.(json.Object)["parent"]
            if !ok {
                log("[INFO] Model '%v' was skipped: could not find parent field", model_name)
                continue
            }

            texture: string
            switch parent.(json.String) {
            case "minecraft:block/cube_all":
                texture = json_data.(json.Object)["textures"].(json.Object)["all"].(json.String)

            case "minecarft:block/cube_column_horizontal": fallthrough
            case "minecraft:block/cube_column":
                switch model_x {
                case 0, 180:
                    texture = json_data.(json.Object)["textures"].(json.Object)["end"].(json.String)
                case:
                    texture = json_data.(json.Object)["textures"].(json.Object)["side"].(json.String)
                }

            case "minecraft:block/cube_bottom_top":
                switch model_x {
                    case 0:
                        texture = json_data.(json.Object)["textures"].(json.Object)["top"].(json.String)

                    case 90:
                        texture = json_data.(json.Object)["textures"].(json.Object)["side"].(json.String)

                    case 180:
                        texture = json_data.(json.Object)["textures"].(json.Object)["bottom"].(json.String)

                    case:
                        unreachable()
                }

            case:
                continue
            }

            if slice.contains(textures[:], texture) {
                log("[INFO] Texture '%v' skipped: already exists", texture)
                continue loop
            }

            strings.builder_reset(&path_builder)
            strings.write_string(&path_builder, BLOCK_TEXTURES_DIR)
            strings.write_string(&path_builder, texture[16:])
            strings.write_string(&path_builder, ".png")
            assert(os.exists(strings.to_string(path_builder)))

            img, err := image.load_from_file(strings.to_string(path_builder))
            if err != nil {
                fmt.printfln("[ERROR] Could not load texture '%v': %v", strings.to_string(path_builder), err)
                continue
            }
            defer image.destroy(img)

            pixel_i := 0
            average_color: [3]uint
            pixel_count: uint
            switch img.channels {
            case 3:
                for ; pixel_i < len(img.pixels.buf); pixel_i += 3 {
                    average_color[0] += uint(img.pixels.buf[pixel_i + 0])
                    average_color[1] += uint(img.pixels.buf[pixel_i + 1])
                    average_color[2] += uint(img.pixels.buf[pixel_i + 2])
                }

                pixel_count = len(img.pixels.buf)/size_of(image.RGB_Pixel)
                average_color[0] /= pixel_count
                average_color[1] /= pixel_count
                average_color[2] /= pixel_count

            case 4:
                for ; pixel_i < len(img.pixels.buf); pixel_i += 4 {
                    average_color[0] += uint(img.pixels.buf[pixel_i + 0])
                    average_color[1] += uint(img.pixels.buf[pixel_i + 1])
                    average_color[2] += uint(img.pixels.buf[pixel_i + 2])

                    if img.pixels.buf[pixel_i + 3] < 0xff {
                        log("[INFO] Texture '%v' was skipped: has transparent pixels", texture)
                        continue loop
                    }
                }

                pixel_count = len(img.pixels.buf)/size_of(image.RGBA_Pixel)
                average_color[0] /= pixel_count
                average_color[1] /= pixel_count
                average_color[2] /= pixel_count

            case:
                unreachable()
            }

            fmt.fprintfln(output_file, "    {{name_with_state=\"minecraft:%v[%v]\", average_color={{%v,%v,%v,255}}}},", block_name, k, average_color[0], average_color[1], average_color[2])
            append(&textures, strings.clone(texture))
        }
    }
    fmt.fprintln(output_file, "}")

    fmt.println("Done")
}
