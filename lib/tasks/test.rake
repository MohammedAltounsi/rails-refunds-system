# tailwindcss-rails enhances `test:prepare` with `tailwindcss:build`, which
# needs the CSS toolchain (bun/lightningcss native module) just to run the Ruby
# test suite. Tests never render CSS, so detach that dependency: `bin/rails test`
# should run the money-path suite even on a machine where the CSS build is broken
# or absent. Assets are still built in `assets:precompile` at deploy time.
if Rake::Task.task_defined?("test:prepare")
  Rake::Task["test:prepare"].prerequisites.delete("tailwindcss:build")
end
