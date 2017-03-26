require 'UtilsMultiGPU'
require 'rnn'
require 'nn'

local function RNNModule(inputDim, hiddenDim, opt)
  
    if opt.nGPU > 0 then
        require 'BatchBRNNReLU'
        return cudnn.BatchBRNNReLU(inputDim, hiddenDim)
    else
        require 'rnn'
        return nn.SeqBRNN(inputDim, hiddenDim)
    end
end

-- Creates the covnet+rnn structure.
local function deepSpeech(opt)
    local conv = nn.Sequential()
    -- (nInputPlane, nOutputPlane, kW, kH, [dW], [dH], [padW], [padH]) conv layers.
    conv:add(nn.SpatialConvolution(1, 32, 11, 41, 2, 2))
    conv:add(nn.SpatialBatchNormalization(32))
    conv:add(nn.Clamp(0, 20))
    
    
    conv:add(nn.SpatialConvolution(32, 32, 11, 21, 2, 1))
    conv:add(nn.SpatialBatchNormalization(32))
    conv:add(nn.Clamp(0, 20))
    local rnnInputSize = 32 * 41 -- based on the above convolutions and 16khz audio.
    local rnnHiddenSize = opt.hiddenSize -- size of rnn hidden layers
    local nbOfHiddenLayers = opt.nbOfHiddenLayers

    conv:add(nn.View(rnnInputSize, -1):setNumInputDims(3)) -- batch x features x seqLength
    conv:add(nn.Transpose({ 2, 3 }, { 1, 2 })) -- seqLength x batch x features
    local rnns = nn.Sequential()
    local rnnModule = RNNModule(rnnInputsize, rnnHiddenSize, opt)
    rnns:add(rnnModule:clone())
    rnnModule = RNNModule(rnnHiddenSize, rnnHiddenSize, opt)

    for i = 1, nbOfHiddenLayers - 1 do
        rnns:add(nn.Bottle(nn.BatchNormalization(rnnHiddenSize), 2))
        rnns:add(rnnModule:clone())
    end
  
    local fullyConnected = nn.Sequential()
    fullyConnected:add(nn.BatchNormalization(rnnHiddenSize))
    --fullyConnected:add(nn.Dropout())
    fullyConnected:add(nn.Linear(rnnHiddenSize, 29))

    local model = nn.Sequential()
    model:add(conv)
    model:add(rnns)
    model:add(nn.Bottle(fullyConnected, 2))    --Bottle can have different dims matrices multiply (3*2*3*4) * (4 *10)  = (3*2*3*10) no need to resize and all
    model:add(nn.Transpose({1, 2})) -- batch x seqLength x features
    model = makeDataParallel(model, opt.nGPU)
    return model
end

-- Based on convolution kernel and strides.
local function calculateInputSizes(sizes)
    sizes = torch.floor((sizes - 11) / 2 + 1) -- conv1
    sizes = torch.floor((sizes - 11) / 2 + 1) -- conv2
    return sizes
end

return { deepSpeech, calculateInputSizes }
