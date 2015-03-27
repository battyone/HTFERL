constant sampler_t normalizedClampedNearestSampler = CLK_NORMALIZED_COORDS_TRUE |
CLK_ADDRESS_CLAMP |
CLK_FILTER_NEAREST;

constant sampler_t normalizedClampedToEdgeNearestSampler = CLK_NORMALIZED_COORDS_TRUE |
CLK_ADDRESS_CLAMP_TO_EDGE |
CLK_FILTER_NEAREST;

constant sampler_t unnormalizedClampedNearestSampler = CLK_NORMALIZED_COORDS_FALSE |
CLK_ADDRESS_CLAMP |
CLK_FILTER_NEAREST;

constant sampler_t defaultNormalizedSampler = CLK_NORMALIZED_COORDS_TRUE |
CLK_ADDRESS_CLAMP_TO_EDGE |
CLK_FILTER_NEAREST;

constant sampler_t defaultUnnormalizedSampler = CLK_NORMALIZED_COORDS_FALSE |
CLK_ADDRESS_CLAMP_TO_EDGE |
CLK_FILTER_NEAREST;

float randFloat(uint2* state) {
	const float invMaxInt = 1.0f / 4294967296.0f;
	uint x = (*state).x * 17 + (*state).y * 13123;
	(*state).x = (x << 13) ^ x;
	(*state).y ^= (x << 7);

	uint tmp = x * (x * x * 15731 + 74323) + 871483;

	return convert_float(tmp) * invMaxInt;
}

float sigmoid(float x) {
	return 1.0f / (1.0f + exp(-x));
}

float boostFunction(float trace, float threshold) {
	return fmin(1.0f, fmax(0.0f, threshold - trace) / threshold);
}

void kernel initializeLayerHidden(write_only image2d_t hiddenFeedForwardActivations,
	write_only image2d_t hiddenFeedBackActivations,
	write_only image2d_t hiddenStates,
	write_only image3d_t feedForwardWeights,
	write_only image2d_t hiddenBiases,
	write_only image3d_t lateralWeights,
	write_only image3d_t feedBackWeights,
	int feedForwardSize, int lateralSize, int feedBackSize,
	uint2 seed, float sparsity, float lateralScalar, float feedBackScalar, float minWeight, float maxWeight)
{
	uint2 seedValue = seed + (uint2)(get_global_id(0) * 29 + 12, get_global_id(1) * 16 + 23) * 36;

	int2 hiddenPosition = (int2)(get_global_id(0), get_global_id(1));

	write_imagef(hiddenFeedForwardActivations, hiddenPosition, (float4)(0.0f, 0.0f, 0.0f, 0.0f));
	write_imagef(hiddenFeedBackActivations, hiddenPosition, (float4)(0.0f, 0.0f, 0.0f, 0.0f));
	write_imagef(hiddenStates, hiddenPosition, (float4)(0.0f, 0.0f, 0.0f, 0.0f));

	float hiddenBias = randFloat(&seedValue) * (maxWeight - minWeight) + minWeight;

	write_imagef(hiddenBiases, hiddenPosition, (float4)(hiddenBias, 0.0f, 0.0f, 0.0f));

	for (int wi = 0; wi < feedForwardSize; wi++) {
		int4 weightPosition = (int4)(hiddenPosition.x, hiddenPosition.y, wi, 0);

		float feedForwardWeight = randFloat(&seedValue) * (maxWeight - minWeight) + minWeight;

		write_imagef(feedForwardWeights, weightPosition, (float4)(feedForwardWeight, 0.0f, 0.0f, 0.0f));
	}

	for (int wi = 0; wi < lateralSize; wi++) {
		int4 weightPosition = (int4)(hiddenPosition.x, hiddenPosition.y, wi, 0);

		float lateralWeight = lateralScalar * (randFloat(&seedValue) * (maxWeight - minWeight) + minWeight);

		write_imagef(lateralWeights, weightPosition, (float4)(lateralWeight, 0.0f, 0.0f, 0.0f));
	}

	for (int wi = 0; wi < feedBackSize; wi++) {
		int4 weightPosition = (int4)(hiddenPosition.x, hiddenPosition.y, wi, 0);

		float feedBackWeight = feedBackScalar * (randFloat(&seedValue) * (maxWeight - minWeight) + minWeight);

		write_imagef(feedBackWeights, weightPosition, (float4)(feedBackWeight, 0.0f, 0.0f, 0.0f));
	}
}

void kernel initializeLayerVisible(write_only image2d_t visibleBiases, write_only image2d_t visibleReconstruction, write_only image3d_t reconstructionWeights,
	int reconstructionSize, uint2 seed, float minWeight, float maxWeight)
{
	uint2 seedValue = seed + (uint2)(get_global_id(0) * 64 + 11, get_global_id(1) * 16 + 4) * 2;

	int2 visiblePosition = (int2)(get_global_id(0), get_global_id(1));

	float bias = randFloat(&seedValue) * (maxWeight - minWeight) + minWeight;

	write_imagef(visibleBiases, visiblePosition, (float4)(bias, 0.0f, 0.0f, 0.0f));

	for (int wi = 0; wi < reconstructionSize; wi++) {
		float weight = randFloat(&seedValue) * (maxWeight - minWeight) + minWeight;

		write_imagef(reconstructionWeights, (int4)(visiblePosition.x, visiblePosition.y, wi, 0), (float4)(weight, 0.0f, 0.0f, 0.0f));
	}

	write_imagef(visibleReconstruction, visiblePosition, (float4)(0.0f, 0.0f, 0.0f, 0.0f));
}

void kernel layerHiddenFeedForwardActivate(read_only image2d_t inputs, read_only image2d_t hiddenStatesPrev, read_only image3d_t feedForwardWeights, read_only image3d_t lateralWeights, read_only image2d_t hiddenBiases, write_only image2d_t hiddenFeedForwardActivations,
	int2 layerSize, float2 layerSizeMinusOneInv, int2 inputSize, int2 inputSizeMinusOne, int receptiveFieldRadius, int lateralConnectionRadius)
{
	int2 hiddenPosition = (int2)(get_global_id(0), get_global_id(1));

	float2 inputCenterPositionNormalized = (float2)(hiddenPosition.x * layerSizeMinusOneInv.x, hiddenPosition.y * layerSizeMinusOneInv.y);
	int2 inputCenterPosition = (int2)(inputCenterPositionNormalized.x * inputSizeMinusOne.x, inputCenterPositionNormalized.y * inputSizeMinusOne.y);

	float sum = 0.0f;

	int wi = 0;

	for (int dx = -receptiveFieldRadius; dx <= receptiveFieldRadius; dx++)
		for (int dy = -receptiveFieldRadius; dy <= receptiveFieldRadius; dy++) {
			int2 inputPosition = (int2)(inputCenterPosition.x + dx, inputCenterPosition.y + dy);

			if (inputPosition.x >= 0 && inputPosition.x < inputSize.x && inputPosition.y >= 0 && inputPosition.y < inputSize.y) {
				float input = read_imagef(inputs, inputPosition).x;

				float weight = read_imagef(feedForwardWeights, (int4)(hiddenPosition.x, hiddenPosition.y, wi, 0)).x;

				sum += weight * input;
			}

			wi++;
		}

	wi = 0;

	for (int dx = -lateralConnectionRadius; dx <= lateralConnectionRadius; dx++)
		for (int dy = -lateralConnectionRadius; dy <= lateralConnectionRadius; dy++) {
			int2 layerPosition = (int2)(hiddenPosition.x + dx, hiddenPosition.y + dy);

			if (layerPosition.x >= 0 && layerPosition.x < layerSize.x && layerPosition.y >= 0 && layerPosition.y < layerSize.y) {
				float state = read_imagef(hiddenStatesPrev, layerPosition).x;

				float weight = read_imagef(lateralWeights, (int4)(hiddenPosition.x, hiddenPosition.y, wi, 0)).x;

				sum += weight * state;
			}

			wi++;
		}

	// Bias
	float bias = read_imagef(hiddenBiases, hiddenPosition).x;

	sum += bias;

	write_imagef(hiddenFeedForwardActivations, hiddenPosition, (float4)(sum, 0.0f, 0.0f, 0.0f));
}

void kernel layerHiddenFeedBackActivate(read_only image2d_t hiddenFeedForwardActivations, read_only image2d_t nextLayerHiddenStates, read_only image3d_t feedBackWeights, write_only image2d_t hiddenFeedBackActivations,
	int2 layerSize, float2 layerSizeMinusOneInv, int2 nextSize, int2 nextSizeMinusOne, int feedBackRadius)
{
	int2 hiddenPosition = (int2)(get_global_id(0), get_global_id(1));

	float2 nextCenterPositionNormalized = (float2)(hiddenPosition.x * layerSizeMinusOneInv.x, hiddenPosition.y * layerSizeMinusOneInv.y);
	int2 nextCenterPosition = (int2)(nextCenterPositionNormalized.x * nextSizeMinusOne.x, nextCenterPositionNormalized.y * nextSizeMinusOne.y);

	float sum = read_imagef(hiddenFeedForwardActivations, hiddenPosition).x;

	int wi = 0;

	for (int dx = -feedBackRadius; dx <= feedBackRadius; dx++)
		for (int dy = -feedBackRadius; dy <= feedBackRadius; dy++) {
			int2 nextPosition = (int2)(nextCenterPosition.x + dx, nextCenterPosition.y + dy);

			if (nextPosition.x >= 0 && nextPosition.x < nextSize.x && nextPosition.y >= 0 && nextPosition.y < nextSize.y) {
				float next = read_imagef(nextLayerHiddenStates, nextPosition).x;

				float weight = read_imagef(feedBackWeights, (int4)(hiddenPosition.x, hiddenPosition.y, wi, 0)).x;

				sum += weight * next;
			}

			wi++;
		}

	write_imagef(hiddenFeedBackActivations, hiddenPosition, (float4)(sum, 0.0f, 0.0f, 0.0f));
}

void kernel layerHiddenInhibit(read_only image2d_t hiddenActivations, write_only image2d_t hiddenStates,
	int2 layerSize, int inhibitionRadius, float localActivity)
{
	int2 hiddenPosition = (int2)(get_global_id(0), get_global_id(1));

	float thisActivation = read_imagef(hiddenActivations, hiddenPosition).x;

	float numHigher = 0.0f;

	for (int dx = -inhibitionRadius; dx <= inhibitionRadius; dx++)
		for (int dy = -inhibitionRadius; dy <= inhibitionRadius; dy++) {
			int2 layerPosition = (int2)(hiddenPosition.x + dx, hiddenPosition.y + dy);

			if (layerPosition.x >= 0 && layerPosition.x < layerSize.x && layerPosition.y >= 0 && layerPosition.y < layerSize.y) {
				float activation = read_imagef(hiddenActivations, layerPosition).x;

				numHigher += activation > thisActivation ? 1.0f : 0.0f;
			}
		}

	float newState = numHigher < localActivity ? 1.0f : 0.0f;

	write_imagef(hiddenStates, hiddenPosition, (float4)(newState, 0.0f, 0.0f, 0.0f));
}

void kernel layerVisibleReconstruct(read_only image2d_t hiddenStates, read_only image3d_t reconstructionWeights, read_only image2d_t visibleBiases, write_only image2d_t visibleReconstruction,
	int reconstructionReceptiveRadius, int2 inputSizeMinusOne, float2 inputSizeMinusOneInv, int2 layerSize, int2 layerSizeMinusOne, float2 layerSizeMinusOneInv)
{
	int2 visiblePosition = (int2)(get_global_id(0), get_global_id(1));
	float2 layerPositionNormalized = (float2)(visiblePosition.x * inputSizeMinusOneInv.x, visiblePosition.y * inputSizeMinusOneInv.y);
	int2 layerPositionCenter = (int2)(layerPositionNormalized.x * layerSizeMinusOne.x, layerPositionNormalized.y * layerSizeMinusOne.y);

	float sum = 0.0f;

	int wi = 0;

	for (int dx = -reconstructionReceptiveRadius; dx <= reconstructionReceptiveRadius; dx++)
		for (int dy = -reconstructionReceptiveRadius; dy <= reconstructionReceptiveRadius; dy++) {
			int2 layerPosition = (int2)(layerPositionCenter.x + dx, layerPositionCenter.y + dy);

			if (layerPosition.x >= 0 && layerPosition.x < layerSize.x && layerPosition.y >= 0 && layerPosition.y < layerSize.y) {
				float source = read_imagef(hiddenStates, layerPosition).x;

				float weight = read_imagef(reconstructionWeights, (int4)(visiblePosition.x, visiblePosition.y, wi, 0)).x;

				sum += source * weight;
			}

			wi++;
		}

	//float bias = read_imagef(visibleBiases, visiblePosition).x;

	//sum += bias;

	write_imagef(visibleReconstruction, visiblePosition, (float4)(sum, 0.0f, 0.0f, 0.0f));
}

void kernel layerHiddenWeightUpdate(read_only image2d_t visibleReconstruction, read_only image2d_t inputs, read_only image2d_t inputsPrev, read_only image2d_t feedBackActivationsPrev, read_only image2d_t hiddenStatesPrev, read_only image2d_t hiddenStatesPrevPrev, read_only image2d_t nextLayerHiddenStatesPrev,
	read_only image3d_t reconstructionWeightsPrev, read_only image3d_t feedForwardWeightsPrev, read_only image3d_t lateralWeightsPrev, read_only image2d_t hiddenBiasesPrev, read_only image3d_t feedBackWeightsPrev,
	write_only image3d_t feedForwardWeights, write_only image3d_t lateralWeights, write_only image2d_t hiddenBiases, write_only image3d_t feedBackWeights,
	int2 layerSize, int2 layerSizeMinusOne, float2 layerSizeMinusOneInv, int2 inputSize, int2 inputSizeMinusOne, float2 inputSizeMinusOneInv, int2 nextSize, int2 nextSizeMinusOne, int receptiveFieldRadius, int lateralConnectionRadius, int feedBackRadius, int reconstructionReceptiveRadius, float sparsity, float4 alpha, float4 momenta, float minDerivative)
{
	int2 hiddenPosition = (int2)(get_global_id(0), get_global_id(1));

	float2 inputCenterPositionNormalized = (float2)(hiddenPosition.x * layerSizeMinusOneInv.x, hiddenPosition.y * layerSizeMinusOneInv.y);
	int2 inputCenterPosition = (int2)(inputCenterPositionNormalized.x * inputSizeMinusOne.x, inputCenterPositionNormalized.y * inputSizeMinusOne.y);

	int2 nextCenterPosition = (int2)(inputCenterPositionNormalized.x * nextSizeMinusOne.x, inputCenterPositionNormalized.y * nextSizeMinusOne.y);

	float thisHiddenState = read_imagef(hiddenStatesPrev, hiddenPosition).x;
	float thisActivation = read_imagef(feedBackActivationsPrev, hiddenPosition).x;

	// --------------------------------- Collect Error -------------------------------------

	float sum = 0.0f;

	for (int dx = -receptiveFieldRadius; dx <= receptiveFieldRadius; dx++)
		for (int dy = -receptiveFieldRadius; dy <= receptiveFieldRadius; dy++) {
			int2 inputPosition = (int2)(inputCenterPosition.x + dx, inputCenterPosition.y + dy);

			if (inputPosition.x >= 0 && inputPosition.x < inputSize.x && inputPosition.y >= 0 && inputPosition.y < inputSize.y) {
				// Next layer node's receptive field
				int2 fieldCenter = (int2)(inputPosition.x * inputSizeMinusOneInv.x * layerSizeMinusOne.x, inputPosition.y * inputSizeMinusOneInv.y * layerSizeMinusOne.y);

				int2 fieldLowerBounds = fieldCenter - (int2)(reconstructionReceptiveRadius);
				int2 fieldUpperBounds = fieldCenter + (int2)(reconstructionReceptiveRadius);

				// Check for containment
				if (hiddenPosition.x >= fieldLowerBounds.x && hiddenPosition.x <= fieldUpperBounds.x && hiddenPosition.y >= fieldLowerBounds.y && hiddenPosition.y <= fieldUpperBounds.y) {
					int rdx = hiddenPosition.x - fieldLowerBounds.x;
					int rdy = hiddenPosition.y - fieldLowerBounds.y;

					float input = read_imagef(inputs, inputPosition).x;
					float recon = read_imagef(visibleReconstruction, inputPosition).x;

					int weightIndex = rdy + rdx * (reconstructionReceptiveRadius * 2 + 1);

					float weight = read_imagef(reconstructionWeightsPrev, (int4)(inputPosition.x, inputPosition.y, weightIndex, 0)).x;

					sum += (input - recon) * weight;
				}
			}
		}

	float error = thisHiddenState * sum - thisActivation * minDerivative;

	// --------------------------------- Update on Error ---------------------------------

	int wi = 0;

	for (int dx = -receptiveFieldRadius; dx <= receptiveFieldRadius; dx++)
		for (int dy = -receptiveFieldRadius; dy <= receptiveFieldRadius; dy++) {
			int2 inputPosition = (int2)(inputCenterPosition.x + dx, inputCenterPosition.y + dy);

			if (inputPosition.x >= 0 && inputPosition.x < inputSize.x && inputPosition.y >= 0 && inputPosition.y < inputSize.y) {
				float input = read_imagef(inputsPrev, inputPosition).x;

				float eligibility = error * input;

				float2 prevWeight = read_imagef(feedForwardWeightsPrev, (int4)(hiddenPosition.x, hiddenPosition.y, wi, 0)).xy;

				float newWeight = prevWeight.x + alpha.x * eligibility + momenta.x * prevWeight.y;
				float newDelta = newWeight - prevWeight.x;

				write_imagef(feedForwardWeights, (int4)(hiddenPosition.x, hiddenPosition.y, wi, 0), (float4)(newWeight, newDelta, 0.0f, 0.0f));
			}

			wi++;
		}

	wi = 0;

	for (int dx = -lateralConnectionRadius; dx <= lateralConnectionRadius; dx++)
		for (int dy = -lateralConnectionRadius; dy <= lateralConnectionRadius; dy++) {
			int2 layerPosition = (int2)(hiddenPosition.x + dx, hiddenPosition.y + dy);

			if (layerPosition.x >= 0 && layerPosition.x < layerSize.x && layerPosition.y >= 0 && layerPosition.y < layerSize.y) {
				float input = read_imagef(hiddenStatesPrevPrev, layerPosition).x;

				float eligibility = error * input;

				float2 prevWeight = read_imagef(lateralWeightsPrev, (int4)(hiddenPosition.x, hiddenPosition.y, wi, 0)).xy;

				float newWeight = prevWeight.x + alpha.x * eligibility + momenta.y * prevWeight.y;
				float newDelta = newWeight - prevWeight.x;

				write_imagef(lateralWeights, (int4)(hiddenPosition.x, hiddenPosition.y, wi, 0), (float4)(newWeight, newDelta, 0.0f, 0.0f));
			}

			wi++;
		}

	wi = 0;

	for (int dx = -feedBackRadius; dx <= feedBackRadius; dx++)
		for (int dy = -feedBackRadius; dy <= feedBackRadius; dy++) {
			int2 nextPosition = (int2)(nextCenterPosition.x + dx, nextCenterPosition.y + dy);

			if (nextPosition.x >= 0 && nextPosition.x < nextSize.x && nextPosition.y >= 0 && nextPosition.y < nextSize.y) {
				float next = read_imagef(nextLayerHiddenStatesPrev, nextPosition).x;

				float eligibility = error * next;

				float2 prevWeight = read_imagef(feedBackWeightsPrev, (int4)(hiddenPosition.x, hiddenPosition.y, wi, 0)).xy;

				float newWeight = prevWeight.x + alpha.x * eligibility + momenta.z * prevWeight.y;
				float newDelta = newWeight - prevWeight.x;

				write_imagef(feedBackWeights, (int4)(hiddenPosition.x, hiddenPosition.y, wi, 0), (float4)(newWeight, newDelta, 0.0f, 0.0f));
			}

			wi++;
		}

	float eligibility = error;

	float2 prevBias = read_imagef(hiddenBiasesPrev, hiddenPosition).xy;

	float newBias = prevBias.x + alpha.w * eligibility + momenta.w * prevBias.y;
	float newDelta = newBias - prevBias.x;

	write_imagef(hiddenBiases, hiddenPosition, (float4)(newBias, newDelta, 0.0f, 0.0f));
}

void kernel layerHiddenWeightUpdateLast(read_only image2d_t visibleReconstruction, read_only image2d_t inputs, read_only image2d_t inputsPrev, read_only image2d_t feedBackActivationsPrev, read_only image2d_t hiddenStatesPrev, read_only image2d_t hiddenStatesPrevPrev,
	read_only image3d_t reconstructionWeightsPrev, read_only image3d_t feedForwardWeightsPrev, read_only image3d_t lateralWeightsPrev, read_only image2d_t hiddenBiasesPrev,
	write_only image3d_t feedForwardWeights, write_only image3d_t lateralWeights, write_only image2d_t hiddenBiases,
	int2 layerSize, int2 layerSizeMinusOne, float2 layerSizeMinusOneInv, int2 inputSize, int2 inputSizeMinusOne, float2 inputSizeMinusOneInv, int receptiveFieldRadius, int lateralConnectionRadius, int reconstructionReceptiveRadius, float sparsity, float4 alpha, float4 momenta, float minDerivative)
{
	int2 hiddenPosition = (int2)(get_global_id(0), get_global_id(1));

	float2 inputCenterPositionNormalized = (float2)(hiddenPosition.x * layerSizeMinusOneInv.x, hiddenPosition.y * layerSizeMinusOneInv.y);
	int2 inputCenterPosition = (int2)(inputCenterPositionNormalized.x * inputSizeMinusOne.x, inputCenterPositionNormalized.y * inputSizeMinusOne.y);

	float thisHiddenState = read_imagef(hiddenStatesPrev, hiddenPosition).x;
	float thisActivation = read_imagef(feedBackActivationsPrev, hiddenPosition).x;

	// --------------------------------- Collect Error -------------------------------------

	float sum = 0.0f;

	for (int dx = -receptiveFieldRadius; dx <= receptiveFieldRadius; dx++)
		for (int dy = -receptiveFieldRadius; dy <= receptiveFieldRadius; dy++) {
			int2 inputPosition = (int2)(inputCenterPosition.x + dx, inputCenterPosition.y + dy);

			if (inputPosition.x >= 0 && inputPosition.x < inputSize.x && inputPosition.y >= 0 && inputPosition.y < inputSize.y) {
				// Next layer node's receptive field
				int2 fieldCenter = (int2)(inputPosition.x * inputSizeMinusOneInv.x * layerSizeMinusOne.x, inputPosition.y * inputSizeMinusOneInv.y * layerSizeMinusOne.y);

				int2 fieldLowerBounds = fieldCenter - (int2)(reconstructionReceptiveRadius);
				int2 fieldUpperBounds = fieldCenter + (int2)(reconstructionReceptiveRadius);

				// Check for containment
				if (hiddenPosition.x >= fieldLowerBounds.x && hiddenPosition.x <= fieldUpperBounds.x && hiddenPosition.y >= fieldLowerBounds.y && hiddenPosition.y <= fieldUpperBounds.y) {
					int rdx = hiddenPosition.x - fieldLowerBounds.x;
					int rdy = hiddenPosition.y - fieldLowerBounds.y;

					float input = read_imagef(inputs, inputPosition).x;
					float recon = read_imagef(visibleReconstruction, inputPosition).x;

					int weightIndex = rdy + rdx * (reconstructionReceptiveRadius * 2 + 1);

					float weight = read_imagef(reconstructionWeightsPrev, (int4)(inputPosition.x, inputPosition.y, weightIndex, 0)).x;

					sum += (input - recon) * weight;
				}
			}
		}

	float error = thisHiddenState * sum - thisActivation * minDerivative;

	// --------------------------------- Update on Error ---------------------------------

	int wi = 0;

	for (int dx = -receptiveFieldRadius; dx <= receptiveFieldRadius; dx++)
		for (int dy = -receptiveFieldRadius; dy <= receptiveFieldRadius; dy++) {
			int2 inputPosition = (int2)(inputCenterPosition.x + dx, inputCenterPosition.y + dy);

			if (inputPosition.x >= 0 && inputPosition.x < inputSize.x && inputPosition.y >= 0 && inputPosition.y < inputSize.y) {
				float input = read_imagef(inputsPrev, inputPosition).x;

				float eligibility = error * input;

				float2 prevWeight = read_imagef(feedForwardWeightsPrev, (int4)(hiddenPosition.x, hiddenPosition.y, wi, 0)).xy;

				float newWeight = prevWeight.x + alpha.x * eligibility + momenta.x * prevWeight.y;
				float newDelta = newWeight - prevWeight.x;

				write_imagef(feedForwardWeights, (int4)(hiddenPosition.x, hiddenPosition.y, wi, 0), (float4)(newWeight, newDelta, 0.0f, 0.0f));
			}

			wi++;
		}

	wi = 0;

	for (int dx = -lateralConnectionRadius; dx <= lateralConnectionRadius; dx++)
		for (int dy = -lateralConnectionRadius; dy <= lateralConnectionRadius; dy++) {
			int2 layerPosition = (int2)(hiddenPosition.x + dx, hiddenPosition.y + dy);

			if (layerPosition.x >= 0 && layerPosition.x < layerSize.x && layerPosition.y >= 0 && layerPosition.y < layerSize.y) {
				float input = read_imagef(hiddenStatesPrevPrev, layerPosition).x;

				float eligibility = error * input;

				float2 prevWeight = read_imagef(lateralWeightsPrev, (int4)(hiddenPosition.x, hiddenPosition.y, wi, 0)).xy;

				float newWeight = prevWeight.x + alpha.x * eligibility + momenta.y * prevWeight.y;
				float newDelta = newWeight - prevWeight.x;

				write_imagef(lateralWeights, (int4)(hiddenPosition.x, hiddenPosition.y, wi, 0), (float4)(newWeight, newDelta, 0.0f, 0.0f));
			}

			wi++;
		}

	float eligibility = error;

	float2 prevBias = read_imagef(hiddenBiasesPrev, hiddenPosition).xy;

	float newBias = prevBias.x + alpha.w * eligibility + momenta.w * prevBias.y;
	float newDelta = newBias - prevBias.x;

	write_imagef(hiddenBiases, hiddenPosition, (float4)(newBias, newDelta, 0.0f, 0.0f));
}

void kernel layerVisibleWeightUpdate(read_only image2d_t visibleReconstruction, read_only image2d_t inputs, read_only image2d_t hiddenStatesPrev, read_only image3d_t reconstructionWeightsPrev, read_only image2d_t visibleBiasesPrev, write_only image3d_t reconstructionWeights, write_only image2d_t visibleBiases,
	int reconstructionReceptiveRadius, int2 inputSizeMinusOne, float2 inputSizeMinusOneInv, int2 layerSize, int2 layerSizeMinusOne, float2 layerSizeMinusOneInv, float alpha, float momentum)
{
	int2 visiblePosition = (int2)(get_global_id(0), get_global_id(1));
	float2 layerPositionNormalized = (float2)(visiblePosition.x * inputSizeMinusOneInv.x, visiblePosition.y * inputSizeMinusOneInv.y);
	int2 layerPositionCenter = (int2)(layerPositionNormalized.x * layerSizeMinusOne.x, layerPositionNormalized.y * layerSizeMinusOne.y);

	float input = read_imagef(inputs, visiblePosition).x;
	float recon = read_imagef(visibleReconstruction, visiblePosition).x;

	float error = input - recon;

	int wi = 0;

	for (int dx = -reconstructionReceptiveRadius; dx <= reconstructionReceptiveRadius; dx++)
		for (int dy = -reconstructionReceptiveRadius; dy <= reconstructionReceptiveRadius; dy++) {
			int2 layerPosition = (int2)(layerPositionCenter.x + dx, layerPositionCenter.y + dy);

			if (layerPosition.x >= 0 && layerPosition.x < layerSize.x && layerPosition.y >= 0 && layerPosition.y < layerSize.y) {
				float source = read_imagef(hiddenStatesPrev, layerPosition).x;

				float eligibility = error * source;

				float2 prevWeight = read_imagef(reconstructionWeightsPrev, (int4)(visiblePosition.x, visiblePosition.y, wi, 0)).xy;

				float newWeight = prevWeight.x + alpha * eligibility + momentum * prevWeight.y;
				float newDelta = newWeight - prevWeight.x;

				write_imagef(reconstructionWeights, (int4)(visiblePosition.x, visiblePosition.y, wi, 0), (float4)(newWeight, newDelta, 0.0f, 0.0f));
			}

			wi++;
		}

	float eligibility = error;

	float2 prevBias = read_imagef(visibleBiasesPrev, visiblePosition).xy;

	float newBias = prevBias.x + alpha * eligibility + momentum * prevBias.y;
	float newDelta = newBias - prevBias.x;

	write_imagef(visibleBiases, visiblePosition, (float4)(newBias, 0.0f, 0.0f, 0.0f));
}

void kernel gaussianBlurX(read_only image2d_t source, write_only image2d_t destination, float2 sizeInv, float kernelWidth) {
	int2 destinationPosition = (int2)(get_global_id(0), get_global_id(1));
	float2 destinationPositionNormalized = (float2)(destinationPosition.x * sizeInv.x, destinationPosition.y * sizeInv.y);

	float4 sum = (float4)(0.0f, 0.0f, 0.0f, 0.0f);

	sum += read_imagef(source, defaultNormalizedSampler, (float2)(destinationPositionNormalized.x - 4.0f * kernelWidth, destinationPositionNormalized.y)) * 0.05f;
	sum += read_imagef(source, defaultNormalizedSampler, (float2)(destinationPositionNormalized.x - 3.0f * kernelWidth, destinationPositionNormalized.y)) * 0.09f;
	sum += read_imagef(source, defaultNormalizedSampler, (float2)(destinationPositionNormalized.x - 2.0f * kernelWidth, destinationPositionNormalized.y)) * 0.12f;
	sum += read_imagef(source, defaultNormalizedSampler, (float2)(destinationPositionNormalized.x - kernelWidth, destinationPositionNormalized.y)) * 0.15f;
	sum += read_imagef(source, defaultNormalizedSampler, (float2)(destinationPositionNormalized.x, destinationPositionNormalized.y)) * 0.16f;
	sum += read_imagef(source, defaultNormalizedSampler, (float2)(destinationPositionNormalized.x + kernelWidth, destinationPositionNormalized.y)) * 0.15f;
	sum += read_imagef(source, defaultNormalizedSampler, (float2)(destinationPositionNormalized.x + 2.0f * kernelWidth, destinationPositionNormalized.y)) * 0.12f;
	sum += read_imagef(source, defaultNormalizedSampler, (float2)(destinationPositionNormalized.x + 3.0f * kernelWidth, destinationPositionNormalized.y)) * 0.09f;
	sum += read_imagef(source, defaultNormalizedSampler, (float2)(destinationPositionNormalized.x + 4.0f * kernelWidth, destinationPositionNormalized.y)) * 0.05f;

	write_imagef(destination, destinationPosition, sum);
}

void kernel gaussianBlurY(read_only image2d_t source, write_only image2d_t destination, float2 sizeInv, float kernelWidth) {
	int2 destinationPosition = (int2)(get_global_id(0), get_global_id(1));
	float2 destinationPositionNormalized = (float2)(destinationPosition.x * sizeInv.x, destinationPosition.y * sizeInv.y);

	float4 sum = (float4)(0.0f, 0.0f, 0.0f, 0.0f);

	sum += read_imagef(source, defaultNormalizedSampler, (float2)(destinationPositionNormalized.x, destinationPositionNormalized.y - 4.0f * kernelWidth)) * 0.05f;
	sum += read_imagef(source, defaultNormalizedSampler, (float2)(destinationPositionNormalized.x, destinationPositionNormalized.y - 3.0f * kernelWidth)) * 0.09f;
	sum += read_imagef(source, defaultNormalizedSampler, (float2)(destinationPositionNormalized.x, destinationPositionNormalized.y - 2.0f * kernelWidth)) * 0.12f;
	sum += read_imagef(source, defaultNormalizedSampler, (float2)(destinationPositionNormalized.x, destinationPositionNormalized.y - kernelWidth)) * 0.15f;
	sum += read_imagef(source, defaultNormalizedSampler, (float2)(destinationPositionNormalized.x, destinationPositionNormalized.y)) * 0.16f;
	sum += read_imagef(source, defaultNormalizedSampler, (float2)(destinationPositionNormalized.x, destinationPositionNormalized.y + kernelWidth)) * 0.15f;
	sum += read_imagef(source, defaultNormalizedSampler, (float2)(destinationPositionNormalized.x, destinationPositionNormalized.y + 2.0f * kernelWidth)) * 0.12f;
	sum += read_imagef(source, defaultNormalizedSampler, (float2)(destinationPositionNormalized.x, destinationPositionNormalized.y + 3.0f * kernelWidth)) * 0.09f;
	sum += read_imagef(source, defaultNormalizedSampler, (float2)(destinationPositionNormalized.x, destinationPositionNormalized.y + 4.0f * kernelWidth)) * 0.05f;

	write_imagef(destination, destinationPosition, sum);
}