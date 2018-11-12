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
  
  s.requires_arc = ['BlockRetainSelf/BRSIntercepter.{h,m,mm}']
  s.source_files = 'BlockRetainSelf/*.{h,m,mm,cpp}'

end
