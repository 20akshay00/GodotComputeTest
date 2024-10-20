extends Node2D

@export_category("Settings")
@export_range(1, 1000) var update_frequency: int = 10
@export var auto_start: bool = true

var _prev_data := PackedByteArray()
var _initial_data := PackedByteArray()

var _grid_width: int
@export var aspect_ratio: float = 1920./1080.
@export_range(20, 570) var _grid_height: int = 200 :
	set(value):
		_grid_height = value
		_grid_width = floor(value * aspect_ratio)

@export_category("Requirements")
@export_file var _compute_shader_path: String
@export var _renderer: ColorRect

var _rd: RenderingDevice

var _input_texture: RID
var _output_texture: RID
var _parameters: RID

var _uniform_set: RID
var _compute_shader: RID
var _pipeline: RID

var _uniform_bindings: Array[RDUniform] = []

var _input_image: Image
var _output_image: Image
var _render_texture: ImageTexture

var _input_format: RDTextureFormat
var _output_format: RDTextureFormat

var _is_processing: bool = false
var _can_process: bool = false 

var _texture_usage := (RenderingDevice.TextureUsageBits.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TextureUsageBits.TEXTURE_USAGE_CAN_UPDATE_BIT | RenderingDevice.TextureUsageBits.TEXTURE_USAGE_CAN_COPY_FROM_BIT) as RenderingDevice.TextureUsageBits

# user interactivity
var _points_to_place: Array[Vector2i] = []
var _points_to_remove: Array[Vector2i] = []

func _ready() -> void:
	_renderer.material.set_shader_parameter("gridSize", Vector2i(_grid_width, _grid_height))
	create_and_validate_image()
	setup_compute_shader()
	
	if not auto_start: return
	_can_process = true  

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST || what == NOTIFICATION_PREDELETE:
		clean_up_gpu()

func _process(_delta: float) -> void:
	if not _is_processing and _can_process:
		_is_processing = true
		update()
		get_tree().create_timer(1./update_frequency).timeout.connect(func(): _is_processing = false)
		render(true)
		 
	if Input.is_action_just_pressed("start"):
		_can_process = not _can_process
	
	if Input.is_action_pressed("remove"):
		var cell_idx := Vector2i(float(_grid_height)/1080. * get_global_mouse_position()) 
		if not (cell_idx.x < 0 or cell_idx.x >= _grid_width or cell_idx.y < 0 or cell_idx.y >= _grid_height):
			_queue_remove_point(cell_idx)
			if not _can_process: render(false)

	elif Input.is_action_pressed("place"):
		var cell_idx := Vector2i(float(_grid_height)/1080. * get_global_mouse_position()) 
		if not (cell_idx.x < 0 or cell_idx.x >= _grid_width or cell_idx.y < 0 or cell_idx.y >= _grid_height):
			_queue_place_point(cell_idx)
			if not _can_process: render(false)

func merge_images() -> void:
	var output_width: int = _output_image.get_width()
	var output_height: int = _output_image.get_height()

	var input_width: int = _input_image.get_width()
	var input_height: int = _input_image.get_height()
	
	var startX := (output_width - input_width) / 2. as int
	var startY := (output_height - input_height) / 2. as int 
	
	for x in input_width:
		for y in input_height:
			var color: Color = _input_image.get_pixel(x, y)
			var destX: int = startX + x
			var destY: int = startY + y
			
			if (destX >= 0 && destX < output_width && destY >= 0 && destY < output_height):
				_output_image.set_pixel(destX, destY, color)
	
	_input_image.set_data(_grid_width, _grid_height, false, Image.FORMAT_L8, _output_image.get_data())

func link_output_texture_to_renderer() -> void:
	_render_texture = ImageTexture.create_from_image(_output_image)
	_renderer.material.set_shader_parameter("binaryDataTexture", _render_texture)

func create_and_validate_image() -> void:
	_output_image = Image.create(_grid_width, _grid_height, false, Image.FORMAT_L8)
	if _initial_data.is_empty():
		var noise := FastNoiseLite.new()
		noise.frequency = 0.1
		noise.seed = randi()
		
		_input_image = noise.get_image(_grid_width, _grid_height)
	else:
		var _image = Image.create_from_data(_grid_width, _grid_height, false, Image.FORMAT_L8, _initial_data)
		
	merge_images()
	link_output_texture_to_renderer()
	
func create_rendering_device() -> void:
	_rd = RenderingServer.create_local_rendering_device()
	
func create_shader() -> void:
	var shader_file: RDShaderFile = load(_compute_shader_path)
	var spirv: RDShaderSPIRV = shader_file.get_spirv()
	_compute_shader = _rd.shader_create_from_spirv(spirv)

func create_pipeline() -> void:
	_pipeline = _rd.compute_pipeline_create(_compute_shader)

func default_texture_format() -> RDTextureFormat:
	var rdtexture := RDTextureFormat.new()
	rdtexture.set_width(_grid_width)
	rdtexture.set_height(_grid_height)
	rdtexture.format = RenderingDevice.DATA_FORMAT_R8_UNORM
	rdtexture.usage_bits = _texture_usage
	
	return rdtexture

func create_texture_formats() -> void:
	_input_format = default_texture_format()
	_output_format = default_texture_format()

func create_texture_and_uniform(image: Image, format: RDTextureFormat, binding: int) -> RID:
	var view := RDTextureView.new()
	var data: Array[PackedByteArray] = [image.get_data()]
	var texture: RID = _rd.texture_create(format, view, data)
	
	var uniform := RDUniform.new()
	uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	uniform.binding = binding
	uniform.add_id(texture)
	
	_uniform_bindings.append(uniform)
	
	return texture

func create_parameters_and_uniform(binding: int) -> RID:
	var byte_array_int := PackedInt32Array([_grid_width, _grid_height]).to_byte_array()
	var parameter_buffer := _rd.storage_buffer_create(byte_array_int.size(), byte_array_int)

	var uniform := RDUniform.new()
	uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	uniform.binding = binding
	uniform.add_id(parameter_buffer)
	
	_uniform_bindings.append(uniform)
	return parameter_buffer
	
func create_uniforms() -> void:
	_input_texture = create_texture_and_uniform(_input_image, _input_format, 0)
	_output_texture = create_texture_and_uniform(_output_image, _output_format, 1)
	_parameters = create_parameters_and_uniform(2)
	_uniform_set = _rd.uniform_set_create(_uniform_bindings, _compute_shader, 0)
	
func setup_compute_shader() -> void:
	create_rendering_device()
	create_shader()
	create_pipeline()
	create_texture_formats()
	create_uniforms()

func update() -> void:
	var compute_list := _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(compute_list, _pipeline)
	_rd.compute_list_bind_uniform_set(compute_list, _uniform_set, 0)
	_rd.compute_list_dispatch(compute_list, 32, 32, 1)
	_rd.compute_list_end()
	_rd.submit()

func render(retrieve_from_gpu: bool) -> void:
	if retrieve_from_gpu: # if unpaused
		_rd.sync()
		if not _initial_data.is_empty(): # if just unpaused, set input from new initial condition
			_prev_data = _initial_data
			_initial_data = PackedByteArray()
		else:
			_prev_data = _place_and_remove_points(_rd.texture_get_data(_output_texture, 0))
		
		_rd.texture_update(_input_texture, 0, _prev_data)
		_output_image.set_data(_grid_width, _grid_height, false, Image.FORMAT_L8, _prev_data)
	else: # if paused
		if _initial_data.is_empty(): # if just paused, take snapshot of output
			_initial_data = _rd.texture_get_data(_output_texture, 0)
		
		# add and remove points while paused
		_initial_data = _place_and_remove_points(_initial_data)
		_output_image.set_data(_grid_width, _grid_height, false, Image.FORMAT_L8, _initial_data)

	_render_texture.update(_output_image)
 
func clean_up_gpu() -> void:
	process_mode = PROCESS_MODE_DISABLED
	if _rd == null: return
	_rd.free_rid(_input_texture)
	_rd.free_rid(_output_texture)
	_rd.free_rid(_parameters)
	_rd.free_rid(_uniform_set)
	_rd.free_rid(_pipeline)
	_rd.free_rid(_compute_shader)
	_rd.free()
	_rd = null

func _queue_place_point(point: Vector2i) -> void:
	_points_to_place.append(point)

func _queue_remove_point(point: Vector2i) -> void:
	_points_to_remove.append(point)

func _place_and_remove_points(data: PackedByteArray) -> PackedByteArray:
	while(_points_to_place):
		var point: Vector2i = _points_to_place.pop_back()
		data[_grid_width * point.y + point.x] = 255

	while(_points_to_remove):
		var point: Vector2i = _points_to_remove.pop_back()
		data[_grid_width * point.y + point.x] = 0

	return data
