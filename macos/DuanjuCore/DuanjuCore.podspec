Pod::Spec.new do |spec|
  spec.name = 'DuanjuCore'
  spec.version = '0.2.0'
  spec.summary = '真果鉴本地站源核心'
  spec.homepage = 'https://github.com/fish2018/guoapp'
  spec.author = '真果鉴 contributors'
  spec.source = { :path => '.' }
  spec.license = { :type => 'See application repository' }
  spec.osx.deployment_target = '12.0'
  spec.source_files = 'Sources/**/*.{h,m}'
  spec.public_header_files = 'Sources/*.h'
  spec.vendored_libraries = 'libDuanjuCore.a'
  spec.static_framework = true
  spec.frameworks = 'Foundation', 'CoreFoundation', 'Security'
  spec.libraries = 'resolv'
  spec.user_target_xcconfig = {
    'OTHER_LDFLAGS' => '$(inherited) -Wl,-u,_DuanjuRequest -Wl,-u,_DuanjuFree -Wl,-export_dynamic',
    'STRIP_STYLE' => 'non-global'
  }
end
