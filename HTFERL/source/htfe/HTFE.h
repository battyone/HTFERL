#pragma once

#include "../system/ComputeSystem.h"
#include "../system/ComputeProgram.h"

#include <vector>
#include <list>

#include <random>

#include <memory>

namespace htfe {
	struct LayerDesc {
		int _width, _height;

		int _receptiveFieldRadius;
		int _reconstructionRadius;
		int _lateralConnectionRadius;
		int _inhibitionRadius;
		int _feedBackConnectionRadius;

		float _sparsity;

		float _dutyCycleDecay;
		float _feedForwardAlpha;
		float _lateralAlpha;
		float _feedBackAlpha;
		float _hiddenBiasAlpha;
		float _reconstructionAlpha;
		float _lateralScalar;
		float _feedBackScalar;
		float _minDerivative;

		LayerDesc()
			: _width(16), _height(16), _receptiveFieldRadius(5), _reconstructionRadius(9), _lateralConnectionRadius(7), _inhibitionRadius(5), _feedBackConnectionRadius(7),
			_sparsity(3.01f / 121.0f), _dutyCycleDecay(0.01f),
			_feedForwardAlpha(0.01f), _lateralAlpha(0.005f), _feedBackAlpha(0.01f), _hiddenBiasAlpha(0.005f), _reconstructionAlpha(0.008f),
			_lateralScalar(0.01f), _feedBackScalar(0.01f), _minDerivative(0.003f)
		{}
	};

	struct Layer {
		cl::Image2D _hiddenFeedForwardActivations;
		cl::Image2D _hiddenFeedBackActivations;
		cl::Image2D _hiddenFeedBackActivationsPrev;

		cl::Image2D _hiddenStatesFeedForward;
		cl::Image2D _hiddenStatesFeedForwardPrev;

		cl::Image2D _hiddenStatesFeedBack;
		cl::Image2D _hiddenStatesFeedBackPrev;
		cl::Image2D _hiddenStatesFeedBackPrevPrev;

		cl::Image3D _feedForwardWeights;
		cl::Image3D _feedForwardWeightsPrev;

		cl::Image3D _reconstructionWeights;
		cl::Image3D _reconstructionWeightsPrev;

		cl::Image2D _visibleBiases;
		cl::Image2D _visibleBiasesPrev;

		cl::Image2D _hiddenBiases;
		cl::Image2D _hiddenBiasesPrev;

		cl::Image3D _lateralWeights;
		cl::Image3D _lateralWeightsPrev;

		cl::Image3D _feedBackWeights;
		cl::Image3D _feedBackWeightsPrev;

		cl::Image2D _visibleReconstruction;
		cl::Image2D _visibleReconstructionPrev;
	};

	class HTFE {
	private:
		int _inputWidth, _inputHeight;

		std::vector<LayerDesc> _layerDescs;
		std::vector<Layer> _layers;

		cl::Kernel _layerHiddenFeedForwardActivateKernel;
		cl::Kernel _layerHiddenFeedBackActivateKernel;
		cl::Kernel _layerHiddenInhibitKernel;
		cl::Kernel _layerVisibleReconstructKernel;
		cl::Kernel _layerHiddenWeightUpdateKernel;
		cl::Kernel _layerHiddenWeightUpdateLastKernel;
		cl::Kernel _layerVisibleWeightUpdateKernel;
		cl::Kernel _layerUpdateQKernel;

		std::vector<float> _input;
		std::vector<float> _prediction;

		cl::Image2D _inputImage;
		cl::Image2D _inputImagePrev;

	public:
		void createRandom(sys::ComputeSystem &cs, sys::ComputeProgram &program, int inputWidth, int inputHeight, const std::vector<LayerDesc> &layerDescs, float minInitWeight, float maxInitWeight);

		void activate(sys::ComputeSystem &cs);
		void learn(sys::ComputeSystem &cs);
		void stepEnd();

		int getInputWidth() const {
			return _inputWidth;
		}

		int getInputHeight() const {
			return _inputHeight;
		}

		const std::vector<LayerDesc> &getLayerDescs() const {
			return _layerDescs;
		}

		const std::vector<Layer> &getLayers() const {
			return _layers;
		}

		const cl::Image2D &getInputImage() const {
			return _inputImage;
		}

		void setInput(int i, float value) {
			_input[i] = value;
		}

		void setInput(int x, int y, float value) {
			setInput(x + y * _inputWidth, value);
		}

		float getPrediction(int i) const {
			return _prediction[i];
		}

		float getPrediction(int x, int y) const {
			return getPrediction(x + y * _inputWidth);
		}

		void clearMemory(sys::ComputeSystem &cs);
	};
}