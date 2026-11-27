--- Minimal JNI access from LuaJIT FFI (Android only).
---
--- love-android is built on SDL, which exposes the JNI
--- environment of the app's Java side; from there the JNI
--- C function table lets Lua call arbitrary Java methods.
--- No Java-side changes are required.
---
--- The JNI function table is declared as a padded struct:
--- only the functions we use are named, the gaps are void*
--- arrays sized to match the JNI spec indices. jniSelfCheck
--- verifies every named function sits at its spec index --
--- run it before trusting anything else in this file.

local ffi = require('ffi')

ffi.cdef([[
typedef union jvalue {
  uint8_t z; int8_t b; uint16_t c; int16_t s;
  int32_t i; int64_t j; float f; double d; void* l;
} jvalue;

/* JNI function table, spec indices in comments. */
struct JNIFns {
  void* _pad0[6];
  void* (*FindClass)(void* env, const char* name);          /* 6 */
  void* _pad7[8];                                        /* 7-14 */
  void* (*ExceptionOccurred)(void* env);                   /* 15 */
  void* _pad16[1];
  void  (*ExceptionClear)(void* env);                      /* 17 */
  void* _pad18[3];                                      /* 18-20 */
  void* (*NewGlobalRef)(void* env, void* obj);             /* 21 */
  void  (*DeleteGlobalRef)(void* env, void* obj);          /* 22 */
  void  (*DeleteLocalRef)(void* env, void* obj);           /* 23 */
  void* _pad24[6];                                      /* 24-29 */
  void* (*NewObjectA)(void* env, void* cls, void* mid,
                      jvalue* args);                       /* 30 */
  void* (*GetObjectClass)(void* env, void* obj);            /* 31 */
  void* _pad32[1];
  void* (*GetMethodID)(void* env, void* cls,
                       const char* name, const char* sig); /* 33 */
  void* _pad34[2];                                      /* 34-35 */
  void* (*CallObjectMethodA)(void* env, void* obj,
                             void* mid, jvalue* args);     /* 36 */
  void* _pad37[2];                                      /* 37-38 */
  uint8_t (*CallBooleanMethodA)(void* env, void* obj,
                                void* mid, jvalue* args);  /* 39 */
  void* _pad40[11];                                     /* 40-50 */
  int32_t (*CallIntMethodA)(void* env, void* obj,
                            void* mid, jvalue* args);      /* 51 */
  void* _pad52[11];                                     /* 52-62 */
  void  (*CallVoidMethodA)(void* env, void* obj,
                           void* mid, jvalue* args);       /* 63 */
  void* _pad64[49];                                    /* 64-112 */
  void* (*GetStaticMethodID)(void* env, void* cls,
                       const char* name, const char* sig);/* 113 */
  void* _pad114[2];                                   /* 114-115 */
  void* (*CallStaticObjectMethodA)(void* env, void* cls,
                             void* mid, jvalue* args);    /* 116 */
  void* _pad117[50];                                  /* 117-166 */
  void* (*NewStringUTF)(void* env, const char* s);        /* 167 */
  void* _pad168[1];
  const char* (*GetStringUTFChars)(void* env, void* js,
                                   uint8_t* copy);        /* 169 */
  void  (*ReleaseStringUTFChars)(void* env, void* js,
                                 const char* chars);      /* 170 */
  void* _pad171[5];                                   /* 171-175 */
  void* (*NewByteArray)(void* env, int32_t len);          /* 176 */
  void* _pad177[23];                                  /* 177-199 */
  void  (*GetByteArrayRegion)(void* env, void* arr,
              int32_t start, int32_t len, int8_t* buf);   /* 200 */
  void* _pad201[7];                                   /* 201-207 */
  void  (*SetByteArrayRegion)(void* env, void* arr,
        int32_t start, int32_t len, const int8_t* buf);   /* 208 */
};
typedef struct JNIFns** JEnv;

void* SDL_AndroidGetJNIEnv(void);
void* SDL_AndroidGetActivity(void);
]])

--- Every named entry must sit at its JNI spec index.
--- Blind-coded padding is the #1 error source; this check
--- turns a miscount into a loud startup failure.
function jniSelfCheck()
  local p = ffi.sizeof('void*')
  local spots = {
    FindClass = 6, ExceptionOccurred = 15, ExceptionClear = 17,
    NewGlobalRef = 21, DeleteGlobalRef = 22, DeleteLocalRef = 23,
    NewObjectA = 30, GetObjectClass = 31, GetMethodID = 33, CallObjectMethodA = 36,
    CallBooleanMethodA = 39, CallIntMethodA = 51,
    CallVoidMethodA = 63, GetStaticMethodID = 113,
    CallStaticObjectMethodA = 116, NewStringUTF = 167,
    GetStringUTFChars = 169, ReleaseStringUTFChars = 170,
    NewByteArray = 176, GetByteArrayRegion = 200,
    SetByteArrayRegion = 208,
  }
  for name, index in pairs(spots) do
    local off = ffi.offsetof('struct JNIFns', name)
    assert(off == index * p, 'JNI offset wrong: ' .. name ..
      ' at ' .. off .. ', want ' .. index * p)
  end
  return true
end

local sdl = nil

local function sdlLib()
  if sdl then return sdl end
  local ok, lib = pcall(ffi.load, 'SDL2')
  sdl = ok and lib or ffi.C
  return sdl
end

function jniEnv()
  local env = sdlLib().SDL_AndroidGetJNIEnv()
  assert(env ~= nil, 'no JNI env (not on Android?)')
  return ffi.cast('JEnv', env)
end

function jniActivity()
  local act = sdlLib().SDL_AndroidGetActivity()
  assert(act ~= nil, 'no Android activity')
  return act
end

--- Raise if the last JNI call left a pending Java
--- exception; `stage` names the call for remote debugging.
function jniCheck(env, stage)
  local exc = env[0].ExceptionOccurred(env)
  if exc ~= nil then
    env[0].ExceptionClear(env)
    error('java exception at ' .. stage)
  end
end

function jniClass(env, name)
  local cls = env[0].FindClass(env, name)
  jniCheck(env, 'FindClass ' .. name)
  assert(cls ~= nil, 'class not found: ' .. name)
  return cls
end

function jniMethod(env, cls, name, sig)
  local mid = env[0].GetMethodID(env, cls, name, sig)
  jniCheck(env, 'GetMethodID ' .. name)
  return mid
end

function jniStaticMethod(env, cls, name, sig)
  local mid = env[0].GetStaticMethodID(env, cls, name, sig)
  jniCheck(env, 'GetStaticMethodID ' .. name)
  return mid
end

--- Pack Lua values into a jvalue array. Booleans map to
--- jboolean, numbers to jint, cdata/nil to object refs.
--- Convert strings with jniStr before passing them here.
function jniArgs(...)
  local n = select('#', ...)
  local arr = ffi.new('jvalue[?]', n == 0 and 1 or n)
  for k = 1, n do
    local v = select(k, ...)
    if type(v) == 'boolean' then
      arr[k - 1].z = v and 1 or 0
    elseif type(v) == 'number' then
      arr[k - 1].i = v
    else
      arr[k - 1].l = v
    end
  end
  return arr
end

function jniCallObj(env, obj, mid, ...)
  local r = env[0].CallObjectMethodA(env, obj, mid,
    jniArgs(...))
  jniCheck(env, 'CallObjectMethodA')
  return r
end

function jniCallBool(env, obj, mid, ...)
  local r = env[0].CallBooleanMethodA(env, obj, mid,
    jniArgs(...))
  jniCheck(env, 'CallBooleanMethodA')
  return r ~= 0
end

function jniCallInt(env, obj, mid, ...)
  local r = env[0].CallIntMethodA(env, obj, mid,
    jniArgs(...))
  jniCheck(env, 'CallIntMethodA')
  return tonumber(r)
end

function jniCallVoid(env, obj, mid, ...)
  env[0].CallVoidMethodA(env, obj, mid, jniArgs(...))
  jniCheck(env, 'CallVoidMethodA')
end

function jniNewObj(env, cls, mid, ...)
  local r = env[0].NewObjectA(env, cls, mid, jniArgs(...))
  jniCheck(env, 'NewObjectA')
  return r
end

function jniCallStaticObj(env, cls, mid, ...)
  local r = env[0].CallStaticObjectMethodA(env, cls, mid,
    jniArgs(...))
  jniCheck(env, 'CallStaticObjectMethodA')
  return r
end

function jniStr(env, s)
  return env[0].NewStringUTF(env, s)
end

--- Read a Java string into a Lua one
function jniText(env, js)
  if js == nil then return nil end
  local chars = env[0].GetStringUTFChars(env, js, nil)
  local s = ffi.string(chars)
  env[0].ReleaseStringUTFChars(env, js, chars)
  return s
end

--- Copy a Lua string into a new Java byte array
function jniBytes(env, s)
  local arr = env[0].NewByteArray(env, #s)
  local buf = ffi.new('int8_t[?]', #s)
  ffi.copy(buf, s, #s)
  env[0].SetByteArrayRegion(env, arr, 0, #s, buf)
  return arr
end

--- Read n bytes out of a Java byte array
function jniReadBytes(env, arr, n)
  local buf = ffi.new('int8_t[?]', n)
  env[0].GetByteArrayRegion(env, arr, 0, n, buf)
  return ffi.string(buf, n)
end

function jniGlobal(env, obj)
  return env[0].NewGlobalRef(env, obj)
end

function jniDropGlobal(env, obj)
  if obj ~= nil then env[0].DeleteGlobalRef(env, obj) end
end

function jniDropLocal(env, obj)
  env[0].DeleteLocalRef(env, obj)
end
