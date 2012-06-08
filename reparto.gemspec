
Gem::Specification.new do |s|
  s.name = 'Reparto'
  s.version = '1.0.0'
  s.date = '2012-06-08'
  s.summary = 'Do thing with multiple ssh connections'
  s.description = 'Exectue commands on multiple computers'
  s.authors = ['Bit4bit']
  s.email = 'bit4bit@riseup.net'
  s.files = ['lib/reparto.rb', 'data/Reparto/i18n/es.yml', 'data/Reparto/i18n/en.yml']
  s.has_rdoc = true
  s.extra_rdoc_files = ["README.rdoc"]
  s.executables = ['reparto']
  s.require_paths << '.'
  s.add_dependency("inifile", ">= 0.0.0")
  s.add_dependency("r18n-desktop", ">= 0.0.0")
  s.homepage = 'https://github.com/bit4bit/reparto'
  s.require_paths = ["lib"]
end		       
