require "aws-sdk"
require "dotenv"
Dotenv.load

def local_dir; './_site'; end

def access_key; ENV['AWS_ACCESS_KEY']; end
def secret_key; ENV['AWS_SECRET_KEY']; end
def region;  ENV['AWS_REGION']; end
def bucket_name;  ENV['AWS_BUCKET_NAME']; end

def file_types
  { ".html" => { type: "text/html" },
    ".css" => { type: "text/css" },
    ".js" => { type: "application/javascript" }
  }
end

def traverse_directory(path)
  Dir.entries(path).map do |f|
    next if [".", ".."].include? f
    f_path = File.join(path, f)
    if File.directory? f_path
      traverse_directory f_path
    else
      f_path
    end
  end
end

def gzip(data)
  sio = StringIO.new
  gz = Zlib::GzipWriter.new(sio)
  gz.write(data)
  gz.close
  sio.string
end

def upload_compressed_object(key, f, ext)
  s3.put_object bucket: bucket_name,
                key: key,
                body: gzip(File.read(f)),
                acl: "public-read",
                content_type: file_types[ext][:type],
                content_encoding: "gzip",
                cache_control: "max-age=604800"
end

def upload_object(key, f, ext)
  s3.put_object bucket: bucket_name,
                key: key,
                body: File.open(f),
                acl: "public-read",
                cache_control: "max-age=604800"
end

def s3
  @s3 = Aws::S3::Client.new(
    region: region,
    credentials: Aws::Credentials.new(access_key, secret_key)
  )
end

desc "Deploy via S3"
task :s3 do

  page = s3.list_objects(bucket: bucket_name)

  p "deleting content"
  loop do
    page.contents.each do |ob|
      s3.delete_object bucket: bucket_name, key: ob.key
    end
    break unless page.next_page?
    page = page.next_page
  end

  p "uploading _site"

  traverse_directory(local_dir).flatten.compact.each do |f|
    key = f.gsub(local_dir+"/", "")
    ext = File.extname(f)
    if file_types.keys.include? ext
      upload_compressed_object(key, f, ext)
    else
      upload_object(key, f, ext)
    end
  end

  p "s3 deploy complete"
end

# Shamelessly copied from
# https://gist.github.com/rrevanth/9377cb1f1664bf610e38#file-rakefile-L43
# https://github.com/stereobooster/jekyll-press/issues/26
desc "Minify site"
task :minify do
  puts "\n## Compressing static assets"
  original = 0.0
  compressed = 0
  Dir.glob("_site/**/*.*") do |file|
    case File.extname(file)
    when ".css", ".gif", ".html", ".jpg", ".jpeg", ".js", ".png", ".xml"
      puts "Processing: #{file}"
      original += File.size(file).to_f
      min = Reduce.reduce(file)
      File.open(file, "w") do |f|
        f.write(min)
      end
      compressed += File.size(file)
    else
      puts "Skipping: #{file}"
    end
  end
  puts "Total compression %0.2f\%" % (((original-compressed)/original)*100)
end
