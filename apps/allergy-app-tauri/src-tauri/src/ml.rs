use base64;
use image::{imageops::FilterType, DynamicImage};
use std::path::PathBuf;
use tflite::{
    // context::ElementKind,
    ops::builtin::BuiltinOpResolver,
    FlatBufferModel,
    InterpreterBuilder,
};
use thiserror::Error;
use tracing::{debug, error, info, warn};

#[derive(Error, Debug)]
pub enum ModelError {
    #[error("TFLite error: {0}")]
    TfLite(#[from] tflite::Error),
    #[error("Image processing error: {0}")]
    ImageError(#[from] image::ImageError),
    #[error("IO error: {0}")]
    IoError(#[from] std::io::Error),
    #[error("Model file not found at path: {0}")]
    ModelNotFound(String),
    #[error("Input/Output tensor configuration error: {0}")]
    TensorError(String),
    #[error("Failed to decode base64 image data")]
    Base64DecodeError(#[from] base64::DecodeError),
    #[error("Inference result processing error: {0}")]
    ResultProcessingError(String),
    #[error("Failed to get Tauri resource path: {0}")]
    ResourcePathError(String),
    #[error("Tensor info not found for index {0}")]
    TensorInfoNotFound(i32),
}

#[derive(Debug, Clone, serde::Serialize)]
pub struct Detection {
    pub class_id: i32,
    pub class_name: String,
    pub confidence: f32,
    pub x_min: f32,
    pub y_min: f32,
    pub x_max: f32,
    pub y_max: f32,
}

pub struct ObjectDetector {
    model: Box<FlatBufferModel>,
    resolver: BuiltinOpResolver,
    input_index: i32,
    output_index: i32,
    input_dims: Vec<usize>,
}

impl ObjectDetector {
    pub fn new(model_path: PathBuf) -> Result<Self, ModelError> {
        if !model_path.exists() {
            return Err(ModelError::ModelNotFound(model_path.display().to_string()));
        }
        let model_data = std::fs::read(&model_path).map_err(ModelError::IoError)?;
        let model = Box::new(FlatBufferModel::build_from_buffer(model_data)?);
        let resolver = BuiltinOpResolver::default();

        let (input_index, output_index, input_dims) = {
            let builder = InterpreterBuilder::new(&*model, &resolver)?;
            let mut temp_interpreter = builder.build()?;
            temp_interpreter.allocate_tensors()?;
            let inputs = temp_interpreter.inputs().to_vec();
            let outputs = temp_interpreter.outputs().to_vec();
            if inputs.is_empty() || outputs.is_empty() {
                return Err(ModelError::TensorError(
                    "Model has no inputs or outputs".into(),
                ));
            }
            let input_idx_i32 = inputs[0];
            let output_idx_i32 = outputs[0];
            let input_info = temp_interpreter
                .tensor_info(input_idx_i32)
                .ok_or_else(|| ModelError::TensorInfoNotFound(input_idx_i32))?;
            let dims = input_info
                .dims
                .iter()
                .map(|&d| d as usize)
                .collect::<Vec<_>>();
            if dims.len() != 4 || dims[0] != 1 {
                return Err(ModelError::TensorError(format!(
                    "Unexpected input dimensions: {:?}. Expected [1, H, W, C]",
                    dims
                )));
            }
            info!("Model loaded. Input dimensions: {:?}", dims);
            (input_idx_i32, output_idx_i32, dims)
        };

        Ok(Self {
            model,
            resolver,
            input_index,
            output_index,
            input_dims,
        })
    }

    pub fn detect(&self, image: DynamicImage) -> Result<Vec<Detection>, ModelError> {
        let input_height = self.input_dims[1];
        let input_width = self.input_dims[2];
        let channels = self.input_dims[3];

        if channels != 3 {
            return Err(ModelError::TensorError(format!(
                "Model expects {} channels, but processing assumes 3 (RGB).",
                channels
            )));
        }

        let builder = InterpreterBuilder::new(&*self.model, &self.resolver)?;
        let mut interpreter = builder.build()?;
        interpreter.allocate_tensors()?;

        let resized_img = image.resize_exact(
            input_width as u32,
            input_height as u32,
            FilterType::Triangle,
        );
        let rgb_img = resized_img.to_rgb8();

        let input_info = interpreter
            .tensor_info(self.input_index)
            .ok_or_else(|| ModelError::TensorInfoNotFound(self.input_index))?;

        let input_type_code = input_info.element_kind as u8;

        if input_type_code == 1 {
            let input_data: Vec<f32> = rgb_img
                .pixels()
                .flat_map(|p| p.0.iter().map(|&x| x as f32 / 255.0))
                .collect();
            if input_data.len() != input_height * input_width * channels {
                return Err(ModelError::TensorError(
                    "Input data size mismatch (Float32)".into(),
                ));
            }
            interpreter
                .tensor_data_mut(self.input_index)?
                .copy_from_slice(&input_data);
        } else if input_type_code == 3 {
            warn!(
                "Handling UInt8 input by direct byte copy - quantization parameters NOT applied."
            );
            let input_data: Vec<u8> = rgb_img.into_raw();
            if input_data.len() != input_height * input_width * channels {
                return Err(ModelError::TensorError(
                    "Input data size mismatch (UInt8)".into(),
                ));
            }
            interpreter
                .tensor_data_mut(self.input_index)?
                .copy_from_slice(&input_data);
        } else {
            return Err(ModelError::TensorError(format!(
                "Unsupported input element kind code: {}",
                input_type_code
            )));
        }

        debug!("Invoking TFLite interpreter...");
        interpreter.invoke()?;
        debug!("Interpreter invocation complete.");

        let output_info = interpreter
            .tensor_info(self.output_index)
            .ok_or_else(|| ModelError::TensorInfoNotFound(self.output_index))?;

        let output_type_code = output_info.element_kind as u8;
        if output_type_code != 1 {
            warn!(
                "Expected Float32 output tensor, found type code: {}",
                output_type_code
            );
            return Err(ModelError::TensorError(format!(
                "Unsupported output element kind code: {}. Expected Float32 (code 1).",
                output_type_code
            )));
        }
        debug!("Output tensor info: {:?}", output_info);

        let output_data: &[f32] = interpreter.tensor_data(self.output_index)?;
        debug!("Output tensor data length: {}", output_data.len());

        warn!("YOLOv8 output parsing and NMS not implemented yet. Returning empty detection list.");
        let detections: Vec<Detection> = vec![];

        Ok(detections)
    }
}
