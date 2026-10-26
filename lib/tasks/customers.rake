namespace :customers do
  desc "Create an initial customer and administrative user from environment variables"
  task create_initial: :environment do
    customer_name = ENV.fetch("INITIAL_CUSTOMER_NAME", "Acme Inc").strip
    user_name = ENV.fetch("INITIAL_USER_NAME", "Admin User").strip
    user_email = ENV.fetch("INITIAL_USER_EMAIL", "admin@acme.test").strip.downcase
    user_password = ENV.fetch("INITIAL_USER_PASSWORD", "ChangeMe123!").strip

    puts "==> Setting up initial customer and administrator..."

    customer = Customer.find_or_create_by!(name: customer_name)
    puts "✓ Customer: #{customer.name} (ID: #{customer.id})"

    user = User.find_by(email: user_email)
    if user
      user.update!(name: user_name, password: user_password, customer: customer)
      puts "✓ Existing user updated and associated with #{customer.name}."
    else
      user = customer.users.create!(
        name: user_name,
        email: user_email,
        password: user_password
      )
      puts "✓ New user created."
    end

    puts ""
    puts "=========================================================="
    puts " Initial Customer & User Ready!"
    puts "=========================================================="
    puts " Customer Name : #{customer.name}"
    puts " User Name     : #{user.name}"
    puts " User Email    : #{user.email}"
    puts " User Password : #{user_password}"
    puts " Login URL     : /login"
    puts "=========================================================="
  end
end
