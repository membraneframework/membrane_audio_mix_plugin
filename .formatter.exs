[
  inputs: [
    "{lib,test,config}/**/*.{ex,exs}",
    ".formatter.exs",
    "c_src/**/*.spec.exs",
    "*.exs"
  ],
  import_deps: [:membrane_core, :bundlex, :unifex]
]
