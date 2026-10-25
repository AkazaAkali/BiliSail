Pod::Spec.new do |s|
  s.name = 'bili_mux'
  s.version = '0.1.0'
  s.summary = 'Local MP4 and MKV stream-copy muxing.'
  s.homepage = 'https://github.com/CKopoer/BiliSail'
  s.license = { :type => 'LGPL-2.1-or-later', :file => '../LICENSE-FFmpeg.txt' }
  s.author = { 'BiliSail' => '' }
  s.source = { :path => '.' }
  s.dependency 'Flutter'
  s.platform = :ios, '15.0'
  s.vendored_frameworks = 'Frameworks/BiliMux.framework'
end
