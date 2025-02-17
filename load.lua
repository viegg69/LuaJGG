local parser = require"parser"
return function(src, ...) return function(...) return parser(src):vm(...) end end