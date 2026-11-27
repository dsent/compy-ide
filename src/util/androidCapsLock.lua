-- The activity holds the latch seen by Android's hardware key dispatcher.
require('util.jni')
local method
return function()
  if method == false then return false end
  local env = jniEnv()
  local activity = jniActivity()
  if not method then
    local cls = env[0].GetObjectClass(env, activity)
    method = env[0].GetMethodID(env, cls, 'compyCapsLockOn', '()Z')
    jniDropLocal(env, cls)
    if method == nil then
      -- Older Android players have no latch provider.
      env[0].ExceptionClear(env)
      jniDropLocal(env, activity)
      method = false
      return false
    end
  end
  local on = env[0].CallBooleanMethodA(env, activity, method, nil)
  jniDropLocal(env, activity)
  jniCheck(env, 'compyCapsLockOn')
  return on ~= 0
end
