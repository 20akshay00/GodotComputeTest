#[compute]
#version 450

const vec4 aliveColor = vec4(1.0, 1.0, 1.0, 1.0);
const vec4 deadColor = vec4(0.0, 0.0, 0.0, 1.0);

// specifying invocations, i.e, the number of threads to deploy
layout(local_size_x = 32, local_size_y = 32, local_size_z = 1) in;

layout(set = 0, binding = 0, r8) restrict uniform readonly image2D inputImage;
layout(set = 0, binding = 1, r8) restrict uniform writeonly image2D outputImage;
layout(set = 0, binding = 2) readonly buffer Parameters {
    int gridWidth;
} parameters;

bool isCellAlive(int x, int y) {
    vec4 pixel = imageLoad(inputImage, ivec2(x, y));
    return pixel.r > 0.5;
}

int getLiveNeighbours(int x, int y) {
    int count = 0;
    for (int i = -1; i <= 1; i++) {
        for (int j = -1; j <= 1; j++) {
            // skip the central cell
            if (i == 0 && j == 0) continue;

            int nx = x + i;
            int ny = y + j;

            if (nx >= 0 && nx < parameters.gridWidth && ny >= 0 && ny < parameters.gridWidth) {
                count += int(isCellAlive(nx, ny));
            }
        }
    }

    return count;
}

void main() {
    ivec2 pos = ivec2(gl_GlobalInvocationID.xy);
    if (pos.x >= parameters.gridWidth || pos.y >= parameters.gridWidth) return;

    // get current state of the cell
    bool isAlive = isCellAlive(pos.x, pos.y);
    int liveNeighbours = getLiveNeighbours(pos.x, pos.y);

    // cellular automata rules
    bool nextState = isAlive;
    if (isAlive && (liveNeighbours < 2 || liveNeighbours > 3)) {
        nextState = false;
    } else if (!isAlive && liveNeighbours == 3) {
        nextState = true;
    }

    vec4 newColor = nextState ? aliveColor : deadColor;
    imageStore(outputImage, pos, newColor);
}
