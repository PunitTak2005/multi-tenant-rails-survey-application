namespace :customers do
  desc "Set up initial customer tenants and users for development and testing (idempotent)"
  task setup: :environment do
    puts "==> Provisioning development & test customer tenants..."

    tenants = [
      {
        customer_name: ENV.fetch("CUSTOMER_A_NAME", "Acme Corporation"),
        user_name: ENV.fetch("USER_A_NAME", "Acme Admin"),
        user_email: ENV.fetch("USER_A_EMAIL", "admin@acme.test").downcase,
        user_password: ENV.fetch("USER_A_PASSWORD", "ChangeMe123!")
      },
      {
        customer_name: ENV.fetch("CUSTOMER_B_NAME", "Beta Technologies"),
        user_name: ENV.fetch("USER_B_NAME", "Beta Admin"),
        user_email: ENV.fetch("USER_B_EMAIL", "beta@beta.test").downcase,
        user_password: ENV.fetch("USER_B_PASSWORD", "ChangeMe123!")
      }
    ]

    ActiveRecord::Base.transaction do
      tenants.each do |t|
        customer = Customer.find_or_create_by!(name: t[:customer_name])
        user = User.find_by(email: t[:user_email])

        if user
          user.update!(name: t[:user_name], password: t[:user_password], customer: customer)
          puts "✓ Updated existing user #{user.email} (Tenant: #{customer.name})"
        else
          user = customer.users.create!(
            name: t[:user_name],
            email: t[:user_email],
            password: t[:user_password]
          )
          puts "✓ Created user #{user.email} (Tenant: #{customer.name})"
        end
      end
    end

    puts ""
    puts "=========================================================="
    puts " Initial Tenants & Users Ready (Development / Testing)!"
    puts "=========================================================="
    puts " Tenant A: Acme Corporation"
    puts "   Email   : admin@acme.test"
    puts "   Password: ChangeMe123!"
    puts ""
    puts " Tenant B: Beta Technologies"
    puts "   Email   : beta@beta.test"
    puts "   Password: ChangeMe123!"
    puts ""
    puts " Login URL : /login"
    puts "=========================================================="
  end

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
