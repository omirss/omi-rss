# Local AI Models

This directory contains TensorFlow Lite models and configuration files for offline AI analysis.

## Required Models

The following TFLite models need to be added to this directory:

1. **sentiment_analysis.tflite** - Sentiment classification model
   - Input: Text tokens (512 max length)
   - Output: 3-class probabilities (negative, neutral, positive)

2. **bias_detection.tflite** - Bias detection model
   - Input: Text tokens (512 max length)
   - Output: 5-class bias scores (political, gender, racial, economic, religious)

3. **topic_classification.tflite** - Topic classification model
   - Input: Text tokens (512 max length)
   - Output: 20-class topic probabilities

4. **text_summarization_small.tflite** - Text summarization model
   - Input: Text tokens (512 max length)
   - Output: Summary tokens

5. **ner_model.tflite** - Named Entity Recognition model
   - Input: Text tokens (128 max length per sentence)
   - Output: 7-class entity labels per token (O, PERSON, ORGANIZATION, LOCATION, DATE, TIME, MONEY)

## ML-Algo Models

The following JSON models are used for lightweight analysis:

1. **readability_model.json** - Linear regression for readability scoring
2. **quality_model.json** - Logistic regression for quality assessment

## Configuration Files

- **sentiment_labels.json** - Labels and thresholds for sentiment analysis
- **topic_labels.json** - Topic categories and keywords
- **bias_indicators.json** - Bias detection patterns and indicators
- **vocabulary.json** - Token vocabulary for text preprocessing

## Model Sources

You can obtain compatible models from:
- TensorFlow Hub
- Hugging Face Model Hub (converted to TFLite)
- Google's MediaPipe models
- Custom trained models using TensorFlow Lite Model Maker

## Fallback Behavior

If models are not available, the local AI service will use rule-based algorithms as fallbacks.