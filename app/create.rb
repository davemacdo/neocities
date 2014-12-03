post '/create_validate_all' do
  content_type :json
  fields = params.select {|p| p.match /^username$|^password$|^email$|^new_tags_string$/}

  site = Site.new fields
  return [].to_json if site.valid?
  site.errors.collect {|e| [e.first, e.last.first]}.to_json
end

post '/create_validate' do
  content_type :json

  if !params[:field].match /^username$|^password$|^email$|^new_tags_string$/
    return {error: 'not a valid field'}.to_json
  end  

  site = Site.new(params[:field] => params[:value])
  site.valid?

  field_sym = params[:field].to_sym

  if site.errors[field_sym]
    return {error: site.errors[field_sym].first}.to_json
  end

  {result: 'ok'}.to_json
end

post '/create' do
  content_type :json
  require_unbanned_ip
  dashboard_if_signed_in

  @site = Site.new(
    username: params[:username],
    password: params[:password],
    email: params[:email],
    new_tags_string: params[:tags],
    ip: request.ip
  )

  black_box_answered = BlackBox.valid? params[:blackbox_answer], request.ip
  question_answered_correctly = params[:question_answer] == session[:question_answer]

  if !question_answered_correctly
    question_first_number, question_last_number = generate_question
    return {
      result: 'bad_answer',
      question_first_number: question_first_number,
      question_last_number: question_last_number
    }.to_json
  end

  if !black_box_answered || !@site.valid? || Site.ip_create_limit?(request.ip)
    flash[:error] = 'There was an unknown error, please try again.'
    return {result: 'error'}.to_json
  end

  @site.save

  EmailWorker.perform_async({
    from: 'web@neocities.org',
    reply_to: 'contact@neocities.org',
    to: @site.email,
    subject: "[Neocities] Welcome to Neocities!",
    body: Tilt.new('./views/templates/email_welcome.erb', pretty: true).render(self)
  })

  send_confirmation_email @site

  session[:id] = @site.id
  {result: 'ok'}.to_json
end