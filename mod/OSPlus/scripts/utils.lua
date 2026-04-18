local UEHelpers = require("UEHelpers")

local M = {}

local GetKismetMathLibrary = UEHelpers.GetKismetMathLibrary

function M.makeVec(x, y, z)
    return GetKismetMathLibrary():MakeVector(x, y, z)
end

function M.makeRot(pitch, yaw, roll)
    return GetKismetMathLibrary():MakeRotator(roll, pitch, yaw)
end

function M.getPlayerController()
    return UEHelpers.GetPlayerController()
end

function M.getWorld()
    return UEHelpers.GetWorld()
end

return M
