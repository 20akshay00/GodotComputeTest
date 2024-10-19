shader_type canvas_item;

uniform sampler2D pixelTexture;
uniform vec3 litColor: source_color;
uniform vec3 unlitColor: source_color; 

uniform sampler2D binaryDataTexture;
uniform int gridWidth; // number of pixels

const int cellSize = 8; // in pixels
const float fadeDistance = 32.0; // in pixels

void fragment() {
	vec2 scaledUV = UV * float(gridWidth); // scale UV to match grid size; UV goes from 0 to 1.	
	ivec2 cellIndex = ivec2(floor(scaledUV)); // get the cell ID inside which the current UV lies
	
	// check if UV lies inside the cell or exactly on border
	vec2 cellUV = fract(scaledUV); // maps all values in range [n, n+1] to [0, 1], i.e, the fractional part, i.e, the local UV inside the cell
	bool isInsideCell = all(greaterThanEqual(cellUV, vec2(0.0))) && all(lessThan(cellUV, vec2(1.0))); // consider only one edge to be part of cell; other edge goes to next cell.
	
	// normalized UV to index the binary data texture.. why not just use UV? 
	vec2 binaryDataUV = vec2(cellIndex) / float(gridWidth - 1);
	
	// read the data texture
	float binaryValue = texture(binaryDataTexture, binaryDataUV).r;
	bool isWhite = binaryValue > 0.5;
	
	// get texture color based on the input data
	vec4 color = texture(pixelTexture, cellUV);
	
	if (isWhite && isInsideCell){
		color = vec4(litColor, color.a);
	}
	else {
		color = vec4(unlitColor, color.a);
	}
	
	// apply fade
	
	// compute minimum distance to border for the fade effect
	//float distanceX = min(scaledUV.x, float(gridWidth) - scaledUV.x) * float(cellSize);
	//float distanceY = min(scaledUV.y, float(gridWidth) - scaledUV.y) * float(cellSize);
	//float distanceToBorder = min(distanceX, distanceY);
	
	//float alphaFactor = log(distanceToBorder * 1.0) / log(fadeDistance * 1.0);
	//color.a *= alphaFactor;

	COLOR = color;
}
