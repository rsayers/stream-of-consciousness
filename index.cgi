#!/usr/local/bin/ruby
# -*- mode: ruby; -*-
class StreamOfConsciousness
  @settings = {
    :blog_title => "Blog Title", 
    :blog_description => "A Stream of Consciousness Blog", 
    :blog_language => "en",
    :datadir => "/home/username/blogdata",
    :pagedir => "/home/username/pagedata", 
    :pagevar => "pages",   
    :url => "http://www.mysite.com",
    :num_entries => 10,     
    :plugindir => "/home/username/plugins",
    :themedir =>  "/home/username/theme",
    :rewrite_links=>false
  }        
  attr_accessor :settings, :widgets
  def include_libs
    require 'cgi'
    require 'ftools' if RUBY_VERSION.to_f < 1.9
    require 'erb'
    require 'iconv'
  end

  def initialize
    include_libs
    init_env
    read_config
    init_outputs
    load_plugins
    load_templates
    get_categories
    get_pages
    load_widgets
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
    if ENV['SERVER_SOFTWARE'] =~ /HTTPi/ then
      tmp_path=ENV['SCRIPT_NAME'].split(File.basename(__FILE__))
      ENV['PATH_INFO']='/'
      if (tmp_path.size > 1) then
        ENV['PATH_INFO']=tmp_path.last
      end
    end
    @cgi=CGI.new 
    @path_info=@cgi.path_info.dup
    puts @cgi.header unless @cgi.server_software =~ /HTTPi/
    if @path_info.match(/\/(\d+)$/)
      @pageno=$1.to_i
      @path_info.gsub!(/(\d+)$/,'')
    end   
  end
  
  def init_outputs
    add_output :xml, /\.xml$/ do
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
    @outputs.each_key do |k|
      if @path_info =~ @outputs[k][:rule] then
        @output_mode = k
        puts @outputs[k][:method].call
        break
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

  def widget (name,&block)
     @widgets << { :title=>name, :content=>block }
  end

  def plugin (hook,&block)
     @plugins << { :hook => hook, :code => block }
  end
  
  def load_templates
    # load the embedded templates first
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

    # load user defined tempaltes next
    return if !File.exist?(@settings[:themedir])
    Dir.chdir(@settings[:themedir])
    list=Dir.glob(File.join("**","*.rhtml"))
    list.each do |f|
      name=f.gsub('.rhtml','').to_sym
      @templates[name]=File.read(@settings[:themedir]+'/'+f)
    end
  end
  
  def template(name,&block)
    tpl=ERB.new(@templates[name])
    tpl.result(binding)
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
        @pages << {'filename'=>e.gsub('.txt','.html'),'title'=>File.open(e,"r:utf-8").readline}
      end
    end
  end
  
  def error(msg)
    template(:layout) { msg }
  end
  
  def load_entry(filename)
    ic_ignore = Iconv.new('US-ASCII//IGNORE', 'UTF-8')
    File.open(filename,"r:utf-8") do |f|
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
  blog=StreamOfConsciousness.new
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
    <div id="header">
      <span id="blogtitle"><%=@settings[:blog_title]%></span>
      <span id="blogsubtitle"><%=@settings[:blog_description]%></span>
    </div>
    <div id="content">
      
@@ footer
    </div>
    <div id="footer">
      <a href="http://github.com/rsayers/stream-of-consciousness">Stream of Consciousness</a> - Blogging Minimilism<br>
      Code and content are Public Domain
    </div>
  </body>
</html>

@@ sidebar
<%unless @widgets.nil? %>
   <% @widgets.each do |item| %>
      <p class="sectiontitle"><%=item[:title]%><p>
      <%=item[:content].call %>
   <% end %>
<% end %>

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
<div id="left">
  <%=block.call if block_given? %>	  
</div>
<div id="right">
  <%=template :sidebar %>
</div>
<%=template :footer%>

@@ navigation
<div id="nav">
  <%if @pageno > 1 then%>    
  <a href="<%=navlink(-1)%>">&lt;&lt;Prev</a> 
  <%end;if @pageno < @numpages then %>
	   <a href="<%=navlink(+1)%>">Next &gt;&gt;</a>
	   <%end%>
</div>

@@ page
<div class="post">
  <div class="postheader">
    <div class="title"><a href="<%=@settings[:url]+'/'+@settings[:pagevar]+'/'+@entry.filename%>"><%=@entry.title%></a></div>      
  </div>
  <div class="postbody">
    <%=@entry.body%>
  </div>
</div>

@@ entry
<div class="post">
  <div class="postheader">
    <div class="title"><a href='<%=entrylink(@entry)%>'><%=@entry.title%></a></div>
    <div class="date"><%=@entry.date.strftime('%B %d %Y')%></div>
  </div>
  <div class="postbody">
    <%=@entry.body%>
  </div>
  <div class="postfooter">
    Posted in <a href="<%=@settings[:url]%><%=@entry.category%>"><%=@entry.category%></a>
  </div>
  <hr>
</div>

@@ css
* { font-family: Helvetica; }
a { text-decoration: none; border-bottom: 1px dashed #929292;color:#929292; }
body { padding-left: 10px;  }
#header { margin-bottom: 10px; width: 800px; border-top:5px solid black; background-color: #eeeeee; margin-left: auto; margin-right: auto; text-align:center}
#left { width: 600px; float:left;}
#content { background-color: #FFFFFF; width: 800px; margin-left: auto; margin-right: auto;}
#right {float:right;text-align:center }
#right ul { list-style: none; }
#right ul li { background-color: #eeeeee;width:170px;margin-left:-50px; border-bottom:1px solid black;text-align:left; border-left:2px solid black; padding-left: 10px }
#right ul li a { color: black; text-decoration:none; border-bottom: 0}
.postbody { text-align: justify;font-size:11pt; font-family: times; letter-spacing: 1px; margin-bottom:10px;  }
#footer { clear: both; margin-left: auto; margin-right: auto;}
#blogtitle { font-size: 24pt; font-weight:bold; }
#blogsubtitle { clear:both; display:block; font-family:Times; font-style: italic}
.title { font-weight: bold; float:left;}
.date {float: right; color: #929292}
.postbody{border-top: 2px solid #929292; clear:both;}
.postfooter { text-align: center; margin-bottom:20px;font-weight:bold }
#footer { text-align: center; width:800px; background-color:#eeeeee;border-bottom:5px solid black}
#nav { text-align: center; margin-bottom:10px; }
pre,code {width:500px;overflow:auto; font-family:courier; font-size:11pt;letter-spacing:0px; background-color:#eeeeee}
hr { display:none})
