package main

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"

import "vendor:stb/image"
import rl "vendor:raylib"

nearest_block :: proc(c: rl.Color) -> (result: string) {
    result = blocks[0].name_with_state
    min_length: f32 = 500
    for block in blocks {
        r := f32(c.r) - f32(block.average_color.r)
        g := f32(c.g) - f32(block.average_color.g)
        b := f32(c.b) - f32(block.average_color.b)

        length := rl.Vector3Length(rl.Vector3{r,g,b})
        if length < min_length {
            result = block.name_with_state
            min_length = length
        }
    }

    return
}

open_file :: proc(file_path: string) -> (os.Handle, bool) {
    file, err := os.open(file_path, os.O_CREATE | os.O_WRONLY | os.O_TRUNC, os.S_IRUSR | os.S_IWUSR)
    if err != nil {
        fmt.eprintfln("ERROR: Could not open file '%v': %v", file_path, os.error_string(err))
        return file, false
    }

    return file, true
}

main :: proc() {
    if len(os.args) != 2 {
        fmt.eprintfln("usage: %v <image>", os.args[0])
        return
    }

    width, height: i32
    img := image.load(strings.clone_to_cstring(os.args[1]), &width, &height, nil, 3)
    if img == nil {
        fmt.eprintln("ERROR: Could not load image:", image.failure_reason())
        return
    }
    defer image.image_free(img)

    fmt.printfln("Loaded image %vx%vx%v", width, height, 3)
    fmt.println("Generating .mcfunction files...")

    output_file, ok := open_file(fmt.tprintf("%v.mcfunction", filepath.stem(os.args[1])))
    if !ok { return }

    cmd_count := 0
    if !ok { return }
    for y in 0..<height {
        for x in 0..<width {
            i := (y*width + x) * 3
            color := rl.Color{
                img[i + 0],
                img[i + 1],
                img[i + 2],
                0xff
            }

            cmd_count += 1
            fmt.fprintfln(output_file, "setblock ~-%v ~ ~%v %v", y, x, nearest_block(color))
        }
    }

    os.close(output_file)

    fmt.println("Done")
    fmt.printfln("Generated %v commands", cmd_count)
}
