#!/usr/local/bin/ruby
# -*- mode: ruby; -*-
settings = {
      :blog_title => "Blog Title", 
      :blog_description => "A Stream of Consciousness Blog", 
      :blog_language => "en",
      :datadir => "/path/to/blogdata",
      :pagedir => "/path/to/pagedata", 
      :pagevar => "pages", 
      :file_extension => 'txt',
      :url => "http://www.mysite.com/",
      :num_entries => 10,     
      :plugindir => "/path/to/plugins",
      :themedir =>  "/path/to/theme",
      :rewrite_links=>false
    }        

class StreamOfConsciousness
  attr_accessor :settings, :widgets, :entries
  def include_libs
    require 'cgi'
    require 'ftools' if RUBY_VERSION.to_f < 1.9
    require 'erb'
    require 'iconv'
  end

  def initialize(settings=nil)
    @settings = settings
    include_libs
    init_env
    read_config
    init_outputs
    load_plugins
    load_templates
    get_categories
    get_pages
    load_widgets
    self
  end

  def init_array (*vars)
    vars.each do |var|
      instance_variable_set "@#{var.to_s}", []
    end
  end
      
  def init_env
    init_array :entries, :categories, :widgets, :plugins, :path_info
    @pageno=1
    @numpages=1
    @templates,@outputs={},{}
    @script_path = File.dirname(__FILE__)
    @conf_file = @script_path + '/blog.conf.rb'
    @open_mode = RUBY_VERSION.to_f < 1.9 ? "r" : "r:utf-8"
    if !ENV['PATH_INFO'] then
      tmp_path=(ENV['SCRIPT_NAME'] || '').split(File.basename(__FILE__))
      ENV['PATH_INFO']='/'
      if (tmp_path.size > 1) then
        ENV['PATH_INFO']=tmp_path.last
      end
    end
    @cgi=CGI.new 
    puts @cgi.header unless @cgi.server_software =~ /HTTPi/
    @path_info=@cgi.path_info.dup
    if @path_info.match(/\/(\d+)$/)
      @pageno=$1.to_i
      @path_info.gsub!(/(\d+)$/,'')
    end   
  end
  
  def init_outputs
    add_output :xml, /\.xml/ do
      get_entries File.dirname(@path_info)
      template :rss
    end
    
    add_output :page, /\/pages\// do
      get_page
      template(:layout) {
        @entry=@entries.first
        template(:page)  
      }
    end
    
    add_output :view, /\.html$/ do
      filename=@path_info.gsub('.html','.txt')
      output=''
      if File.exist?(@settings[:datadir]+'/'+filename) then
        get_entry(filename)
        @entry=@entries.first
        template(:layout) { 
          output << do_hook("before_single_entry")
          output << template(:entry) 
          output << do_hook("after_single_entry")    
          output
        }
      else
        error "Error: the requested entry was not found."
      end
    end
    
    add_output :list do
      output=''
      if File.exist?( @settings[:datadir]+'/'+@path_info ) then
        get_entries @path_info   
        do_hook('before_list_entry')
        template(:layout) { 
          @entries.each do |e|
            @entry=e
            output << template(:entry)
          end
          output << template(:navigation)
          output
        }
      else
        error "Error: the specified path was not found"
      end
    end
  end

  def load_widgets
    if (File.exist?(@settings[:pagedir])) then   
      widget 'Pages' do
        "<ul>" + @pages.map { |p| "\t<li><a href=\"#{@settings[:url]}/#{@settings[:pagevar]}/#{p['filename']}\">#{p['title']}</a></li>\n"}.join + "</ul>"
      end
    end
    
    widget 'Categories' do
      "<ul>" + @categories.map { |c|  "\t<li><a href=\"#{@settings[:url]}#{c}\">#{c}</a></li>\n" }.join + "</ul>"
    end
    do_hook('widgets')
  end
  
  def read_config
    eval(File.read(@conf_file)) if File.exist?(@conf_file)
    @settings[:url]+="/#{File.basename(__FILE__)}" if @settings[:rewrite_links]!=true
  end

  def add_output (name,rule=/.*/,&block)
    @output_mode = name
    @outputs[name]={:rule=>rule,:method=>block}
  end

  def dispatch
    @outputs.each_pair do |k,v|
      if @path_info =~ v[:rule] then
        @output_mode = k
        puts v[:method].call
      end
    end
  end
  
  def load_plugins
    return if !File.exist?(@settings[:plugindir])
    Dir.chdir(@settings[:plugindir])
    list=Dir.glob(File.join("**","*.rb"))
    list.each do |f|
      eval(File.read(@settings[:plugindir]+'/'+f))
    end      
  end

  def widget (name,&block); @widgets << { :title=>name, :content=>block };end
  def plugin (hook,&block); @plugins << { :hook => hook, :code => block }; end
  
  def load_templates
    if DATA
      template=nil
      DATA.each_line do |line|
        if line =~ /^@@ \s*(.*)/
          template = $1
          @templates[$1.to_sym] = ""
        elsif template
          @templates[template.to_sym] << line
        end
      end
    end
    return if !File.exist?(@settings[:themedir])
    Dir.chdir(@settings[:themedir])
    list=Dir.glob(File.join("**","*.rhtml"))
    list.each do |f|
      name=f.gsub('.rhtml','').to_sym
      @templates[name]=File.read(@settings[:themedir]+'/'+f)
    end
  end
  
  def template(name,&block)
    tpl=ERB.new(@templates[name]).result(binding)
  end
  
  def do_hook(hook)
    @plugins.reject { |p| p[:hook] != hook }.map{ |p| p[:code].call }.join      
  end
  
  def get_entry(filename)
    @entries << load_entry(@settings[:datadir]+'/'+filename)
  end
  
  def get_page
    filename=@settings[:pagedir]+ '/' + File.basename(@path_info)
    filename.gsub!('.html','.txt')
    @entries << load_entry(filename)
  end
  
  def get_categories
    @categories << '/'
    Dir.chdir(@settings[:datadir])
    list=Dir.glob(File.join("**","*"))
    list.each do |e|
      @categories << '/'+e if FileTest.directory?(@settings[:datadir] + '/' + e)
    end
    @categories.sort! 
  end  
  
  def get_pages
    @pages=[]
    if (File.exist?(@settings[:pagedir])) then  
      Dir.chdir(@settings[:pagedir])
      list=Dir.glob(File.join("**","*.txt"))
      list.each do |e|
        @pages << {'filename'=>e.gsub('.txt','.html'),'title'=>File.open(e,@open_mode).readline}
      end
    end
  end
  
  def error(msg)
    template(:layout) { msg }
  end
  
  def load_entry(filename)
    ic_ignore = Iconv.new('US-ASCII//IGNORE', 'UTF-8')
    File.open(filename,@open_mode) do |f|
      title=f.readline
      body=ic_ignore.iconv(f.read).gsub("\r","").gsub("\n","<br />")
      date=f.mtime
      category='page'
      category=get_cat_from_file(filename) if @output_mode != :page
      tmp,filename=File.split(filename)
      do_hook('load_post')
      Entry.new(title,body,date,category,filename)
    end      
  end
  
  def get_cat_from_file(filename)
    fullpath=File.expand_path(filename)
    tmp,category=fullpath.split(@settings[:datadir])
    category,file=File.split(category)
    category
  end
  
  def get_entries(category='/')
    begin
      Dir.chdir(@settings[:datadir] + '/' + category )
    rescue
    end
    list=Dir.glob(File.join("**","*.#{@settings[:file_extension]}"))
    list.each do |post|
      @entries << load_entry(post)
    end
    @entries.sort! { |x,y| y.date <=> x.date }
    start = (@pageno.to_i * @settings[:num_entries].to_i) - @settings[:num_entries].to_i
    start = 0 if @pageno == 1
    @numpages=(@entries.length.to_f /  @settings[:num_entries].to_f).ceil
    @entries=@entries[start,@settings[:num_entries].to_i]
    do_hook('load_category');
  end

  def entrylink(entry)
    link = []
    link << @settings[:url].gsub(/\/$/,'')
    link << entry.category.gsub(/^\//,'').gsub(/\/$/,'')
    link << entry.filename
    link.join('/')
  end

  def navlink(p)
    link = []
    link << @settings[:url].gsub(/\/$/,'')
    link << @path_info.gsub(/^\//,'').gsub(/\/$/,'') if @path_info!="/"
    link << @pageno.to_i + p
    link.join('/')
  end
end

class Entry
  attr_accessor :title, :body, :date, :category, :filename
  def initialize(title,body,date,category,filename)
    @title=title
    @body=body
    @date=date
    @category=category
    @filename=filename.gsub('.txt','.html')
  end
end

if $0 == __FILE__
  blog=StreamOfConsciousness.new(settings)
  blog.dispatch
end
__END__
@@ header
<!DOCTYPE HTML>
<html>
  <head>
    <meta http-equiv="Content-Type" content="text/html; charset=UTF-8">
    <link rel="alternate" type="application/rss+xml" title="Recent (RSS)" href="/rss.xml" />
    <title><%=@settings[:blog_title]%></title>
    <style  type="text/css">
      <%=template :css %>
    </style>
    <%=do_hook('html_head') %>
  </head>
  <body> 
   <div id="rap">  
    <div id="headwrap">
      <div id="header"><a href="<%=@settings[:url]%>"><%=@settings[:blog_title]%></a></div>
      <div id="desc"><a href="<%=@settings[:url]%>">&raquo; <%=@settings[:blog_description]%></a></div>
    </div> 
      
@@ footer
    <div class="credit">
      Powered By <a href="http://github.com/rsayers/stream-of-consciousness">Stream of Consciousness</a> - Theme "Barecity" by <a href="http://shaheeilyas.com/">Shahee Ilyas</a>, Ported by <a href="http://www.robsayers.com">Rob Sayers</a>
    </div>
</div>
  </body>
</html>

@@ sidebar
<ul>
  <%unless @widgets.nil? %>
    <% @widgets.each do |item| %>
      <li class="widget widget_text"><%=item[:title]%><br />			
        <div class="textwidget"><%=item[:content].call %></div>
     </li>
   <% end %>
<% end %>
</ul>

@@ rss
<?xml version="1.0"?>
<rss version="2.0">
  <channel>
    <title><%=@settings[:blog_title]%></title>
    <link><%=@settings[:url]%></link>
    <description><%=@settings[:blog_description]%></description>
    <pubDate><%=@entries.first.date%></pubDate>
    <generator>Stream of Consciousness</generator>   
    <% @entries.each do |post| %>
    <item>
      <title><%= post.title %></title>
      <link><%= @settings[:url] %><%= post.category %>/<%= post.filename %></link>
      <description><![CDATA[<%= post.body %>]]></description>
      <pubDate><%=post.date%></pubDate>
      <guid><%=@settings[:url]%><%=post.category%>/<%=post.filename%></guid>
    </item>
    <% end %>    
  </channel>
</rss>

@@ layout
<%=template :header%>
<div id="content">
  <%=block.call if block_given? %>
</div>	  
<div id="sidebar">
  <%=template :sidebar %>
</div>

<%=template :footer%>

@@ navigation
  <%if @pageno > 1 then%><a href="<%=navlink(-1)%>">&lt;&lt;Prev</a> <%end%>
  <%if @pageno < @numpages then %><a href="<%=navlink(+1)%>">Next &gt;&gt;</a><%end%>


@@ page
<div class="post">
    <h3 class="title"><a href="<%=@settings[:url]+'/'+@settings[:pagevar]+'/'+@entry.filename%>"><%=@entry.title%></a></h3>      
    <div class="storycontent"><%=@entry.body%></div>
</div>

@@ entry
<div class="post">
  <h3 class="storytitle"><a href='<%=entrylink(@entry)%>'><%=@entry.title%></a></h3>
  <div class="meta"><a href="<%=@settings[:url]%><%=@entry.category%>"><%=@entry.category%></a> &#8212; <%=@entry.date.strftime('%B %d %Y')%></div>
  <div class="storycontent"><p><%=@entry.body%></p></div>
</div>

@@ css
a {text-decoration: none; color: #000;}
a:active, a:visited, a:hover {text-decoration: none;color: #000;}
a img {border: none;}
acronym, abbr, span.caps {font-size: 11px;}
acronym, abbr {cursor: help;border:none;}
blockquote {border-left: 5px solid #ccc;margin-left: 18pxpadding-left: 5px;}
body {background: #fff;color: #000;font-family:  Verdana, Arial, Helvetica, sans-serif;margin: 0;padding: 0;font-size: 12px;}
cite {font-size: 11px;font-style: normal;color:#666;}
h2 {font-family: Verdana, Arial, Helvetica, sans-serif;margin: 15px 0 2px 0;padding-bottom: 2px;}
h3 {font-family: Verdana, Arial, Helvetica, sans-serif;margin-top: 0;font-size: 13px;}
#commentlist li{margin-left:-22px;}
p, li, .feedback {font: 11px Verdana, Arial, Helvetica, sans-serif;}
.credit {clear:both;color: #666;font-size: 10px;padding: 50px 0 0 0;margin: 0 0 20px 0;text-align: left;}
.credit a:link, .credit a:hover {color: #666;}
.meta {font-size: 10px;}
.meta, .meta a {color: #808080;font-weight: normal;letter-spacing: 0;}
.storytitle {margin: 0;}
.storytitle a {text-decoration: none;}
.storycontent a {text-decoration: none;border-bottom: 1px dotted #888;}
.storycontent a:hover {text-decoration: none;border-bottom: 1px dashed #888;}
.storycontent {margin-bottom:-10px;}
.post {margin-bottom:18px;}
#content {float: left;width:600px;}
#header {font-family: Georgia, "Times New Roman", Times, serif;font-size: 34px;color: black;font-weight: normal;}
#headwrap {padding:12px 0 16px 0;margin:24px 0 48px 0;}
#header a {color: black;text-decoration: none;}
#header a:hover {text-decoration: none;}
#sidebar {background: #fff;border-left: 1px dotted #ccc;padding: 0px 0 10px 20px;float: right;width: 144px;}
#sidebar input#s {width: 60%;background: #eee;border: 1px solid #999;color: #000;}
#sidebar ul {color: #ccc;list-style-type: none;margin: 0;padding-left: 3px;text-transform: lowercase;}
#sidebar h2 {font-weight: normal;margin:0;padding:0;font-size: 12px;}
#sidebar ul li {font-family: Verdana, Arial, Helvetica, sans-serif;margin-top: 10px;padding-bottom: 2px;}
#sidebar ul ul {font-variant: normal;font-weight: normal;list-style-type: none;margin: 0;padding: 0;text-align: left;}
#sidebar ul ul li {border: 0;font-family: Verdana, Arial, Helvetica, sans-serif;letter-spacing: 0;margin-top: 0;padding: 0;padding-left: 3px;}
#sidebar ul ul li a {color: #000;text-decoration: none;}
#sidebar ul ul li a:hover {border-bottom: 1px solid #809080;}
#sidebar ul ul ul.children {font-size: 17px;padding-left: 4px;}
#rap {background-color: #FFFFFF;margin-right:auto;margin-left:70px;width:800px;padding: 6px;}
#desc {float:left;font-size: 12px;margin-top:3px;}
#desc a:link, #desc a:visited  {display: inline;background-color: #fff;color: #666;text-decoration: none;}
#desc a:hover {background-color: #eee;color: #666;}
#desc a:active {background-color: #fff;}
