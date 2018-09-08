Pod::Spec.new do |s|

  s.name         = "blockRetainSelf"
  s.version      = "0.0.3"
  s.summary      = "block retain self check for iOS"
  s.description  = <<-DESC
			block retain self check for iOS
                   DESC
  s.homepage     = "https://git.yy.com/fangyang/blockRetainSelf"
  s.license      = { :type => 'MIT', :text => 'LICENSE'}
  s.author       = { "perf" => "fangyang@yy.com" }
  s.platform     = :ios, "7.0"
  s.source       = { :git => "https://git.yy.com/fangyang/blockRetainSelf.git", :tag => "#{s.version}" }
  s.source_files  = 'BlockRetainSelf/*.{h,m,mm,cpp}'

  s.subspec 'no-ARC' do |ss|
  	ss.requires_arc = false
  	ss.source_files = 'BlockRetainSelf/BRStrongReferenceDetector.{h,m,mm}','BlockRetainSelf/BlockRetainSelf.{h,m,mm}'
  end
  s.subspec 'ARC' do |ss|
	ss.requires_arc = true
	ss.source_files = 'BlockRetainSelf/*.{h,m,mm,cpp}'
 	ss.exclude_files = 'BlockRetainSelf/BRStrongReferenceDetector.{h,m,mm}','BlockRetainSelf/BlockRetainSelf.{h,m,mm}'
  end

end
