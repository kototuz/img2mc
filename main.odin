package main

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"

import "vendor:stb/image"
import rl "vendor:raylib"

MAX_COMMAND_COUNT :: 65536

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
    file, err := os.open(file_path, os.O_CREATE | os.O_WRONLY, os.S_IRUSR | os.S_IWUSR)
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

    dir_name := filepath.stem(os.args[1])

    if !os.exists(dir_name) {
        err := os.make_directory(dir_name, 0o777)
        if err != nil {
            fmt.eprintln("ERROR: Could not create directory:", os.error_string(err))
            return
        }
    }

    width, height: i32
    image := image.load(strings.clone_to_cstring(os.args[1]), &width, &height, nil, 3)
    if image == nil {
        fmt.eprintln("ERROR: Could not load image")
        return
    }

    fmt.printfln("Loaded image %vx%vx%v", width, height, 3)
    fmt.println("Generating .mcfunction files...")

    cmd_count := 0
    file_count := 0
    curr_file, ok := open_file(fmt.tprintf("%v/%x.mcfunction", dir_name, 0))
    if !ok { return }
    for y in 0..<height {
        for x in 0..<width {
            i := (y*width + x) * 3
            color := rl.Color{
                image[i + 0],
                image[i + 1],
                image[i + 2],
                0xff
            }

            if cmd_count == MAX_COMMAND_COUNT {
                os.close(curr_file)
                file_count += 1
                curr_file, ok = open_file(fmt.tprintf("%v/%x.mcfunction", dir_name, file_count))
                cmd_count = 0
            }

            cmd_count += 1
            fmt.fprintfln(curr_file, "setblock ~-%v ~ ~%v %v", y, x, nearest_block(color))
        }
    }

    os.close(curr_file)

    fmt.println("Done")
}
