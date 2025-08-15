# config/initializers/grover.rb

Grover.configure do |config|
  config.options = {
    format: 'A4',
    margin: {
      top: '0.5in',
      bottom: '0.5in',
      left: '0.5in',
      right: '0.5in'
    },
    print_background: true,
    prefer_css_page_size: true,
    display_header_footer: false,
    emulate_media: 'print'
  }
end
