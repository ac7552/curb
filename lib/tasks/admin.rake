namespace :curb do
  namespace :admin do
    desc "Make someone an admin: bin/rails 'curb:admin:grant[person@example.com]'"
    task :grant, %i[email] => :environment do |_, args|
      user = User.find_by(email_address: args[:email].to_s.strip.downcase) or abort "No account with that email."
      user.update_column(:admin, true)
      puts "#{user.email_address} is now an admin."
    end
  end
end
