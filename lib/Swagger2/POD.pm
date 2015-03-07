package Swagger2::POD;

=head1 NAME

Swagger2::POD - Convert swagger API spec to Perl documentation

=head1 DESCRIPTION

L<Swagger2::POD> is a module that can convert from L</Swagger2> to L<POD|perlpod>.

=head1 SYNOPSIS

  use Swagger2;
  my $swagger = Sswagger2->new("file:///path/to/api-spec.yaml");

  print $swagger->pod->to_string;

=cut

use Mojo::Base -base;
use Mojo::JSON 'encode_json';
use Mojo::Message::Response;
use Scalar::Util 'blessed';
use constant NO_DESCRIPTION => 'No description.';

my $MOJO_MESSAGE_RESPONSE = Mojo::Message::Response->new;

=head1 METHODS

=head2 to_string

  $str = $self->to_string;

Will convert swagger API spec to plain old documentation.

=cut

sub to_string {
  my $self = shift;

  join('', $self->_header_to_string, $self->_api_endpoint_to_string, $self->_paths_to_string, $self->_footer_to_string,
  );
}

sub _api_endpoint_to_string {
  my $self    = shift;
  my @schemes = @{$self->{tree}->get('/schemes') || []};
  my $url     = $self->{base_url}->clone;
  my $str     = "=head1 BASEURL\n\n";

  unless (@schemes) {
    return $str . "No default URL is defined to this application.\n\n";
  }

  while (my $scheme = shift @schemes) {
    $url->scheme($scheme);
    $str .= sprintf "L<%s>\n\n", $url;
  }

  return $str;
}

sub _footer_to_string {
  my $self    = shift;
  my $contact = $self->{tree}->get('/info/contact');
  my $license = $self->{tree}->get('/info/license');
  my $str     = '';

  unless ($license->{name}) {
    $license->{name} = 'BSD';
    $license->{url}  = 'http://www.linfo.org/bsdlicense.html';
  }

  $contact->{name} ||= 'Unknown author';

  $str .= sprintf "=head1 COPYRIGHT AND LICENSE\n\n%s", $contact->{name};
  $str .= sprintf " - %s",  $contact->{email} || $contact->{url} if $contact->{email} || $contact->{url};
  $str .= sprintf "\n\n%s", $license->{name};
  $str .= sprintf " - %s", $license->{url} if $license->{url};
  $str .= "\n\n=cut\n";
  $str;
}

sub _header_to_string {
  my $self = shift;
  my $info = $self->{tree}->get('/info');
  my $str  = '';

  $info->{title}       ||= 'Noname API';
  $info->{description} ||= 'This API has no description.';
  $info->{version}     ||= '0.01';

  $str .= sprintf "=head1 NAME\n\n%s\n\n",             $info->{title};
  $str .= sprintf "=head1 VERSION\n\n%s\n\n",          $info->{version};
  $str .= sprintf "=head1 DESCRIPTION\n\n%s\n\n",      $info->{description};
  $str .= sprintf "=head1 TERMS OF SERVICE\n\n%s\n\n", $info->{termsOfService} if $info->{termsOfService};
  $str;
}

sub _path_request_to_string {
  my ($self, $info) = @_;
  my @table = ([qw( Name In Type Required Description )]);
  my $str   = '';
  my %body;

  for my $p (@{$info->{parameters} || []}) {
    $p->{description} ||= NO_DESCRIPTION;
    if ($p->{in} eq 'body') {
      %body = (name => 'body', %$p);
      push @table, [$p->{name}, 'body', 'schema', 'Yes', $p->{description}];
    }
    else {
      push @table, [@$p{qw( name in type )}, $p->{required} ? 'Yes' : 'No', $p->{description}];
    }
  }

  $str .= sprintf "=head3 Parameters\n\n";
  $str .= (@table == 1) ? "This resource takes no parameters.\n\n" : sprintf "%s\n", _ascii_table(\@table, '  ');
  $str .= "  $body{name}:\n\n" . $self->_schema_to_string_dispatch($body{schema}, 1) . "\n" if %body;
  $str;
}

sub _path_response_to_string {
  my ($self, $info) = @_;
  my $responses = $info->{responses} || {};
  my $str = '';

  $str .= sprintf "=head3 Responses\n\n";

  for my $code (sort keys %$responses) {
    my $res = $responses->{$code};
    $str .= sprintf "=head4 %s\n\n", _status_code_to_string($code);
    $str .= $self->_summary_and_description($res);
    $str .= $self->_schema_to_string_dispatch($res->{schema}, 1) . "\n";
  }

  return $str;
}

sub _paths_to_string {
  my $self  = shift;
  my $paths = $self->{tree}->get('/paths') || {};
  my $str   = "=head1 RESOURCES\n\n";
  my %info;

  for my $path (keys %$paths) {
    for my $method (sort keys %{$paths->{$path}}) {
      my $operationId = $paths->{$path}{$method}{operationId} || join ' ', uc $method, $path;
      $info{$operationId} and die "Overlapping operationId in swagger specification: $operationId";
      $info{$operationId} = {%{$paths->{$path}{$method}}, _path => $path, _method => $method,};
    }
  }

  for my $operationId (sort keys %info) {
    my $url  = $self->{base_url}->clone;
    my $info = $info{$operationId};
    push @{$url->path->parts}, grep { length $_ } split '/', $info->{_path};

    my $ext = $info->{externalDocs};
    my $resource_url;

    $str .= sprintf "=head2 %s\n\n", $operationId;
    $str .= "  THIS RESOURCE IS DEPRECATED!\n\n" if $info->{deprecated};
    $str .= $self->_summary_and_description($info);
    $str .= sprintf "See also L<%s>\n\n", $ext->{url} if $ext;

    next METHOD if $info->{deprecated};
    $url->query(Mojo::Parameters->new);
    $resource_url = $url->to_abs;
    $resource_url =~ s!/%7B([^%]+)%7D!/{$1}!g;

    $str .= sprintf "=head3 Resource URL\n\n";
    $str .= sprintf "  %s %s\n\n", uc $info->{_method}, $resource_url;
    $str .= $self->_path_request_to_string($info);
    $str .= $self->_path_response_to_string($info);
  }

  return $str;
}

sub _schema_array_to_string {
  my ($self, $schema, $depth) = @_;
  my $description = _type_description($schema, qw( minItems maxItems multipleOf uniqueItems ));
  my $str = '';

  $description = $description eq NO_DESCRIPTION ? "" : "// $description";

  $str .= _sprintf($depth == 1 ? 1 : 0, "[%s\n", $description);
  $str .= _sprintf($depth + 1, "");
  $str .= $self->_schema_to_string_dispatch($schema->{items}, $depth + 1);
  $str .= _sprintf($depth + 1, "...\n");
  $str .= _sprintf($depth,     "]\n");
  $str;
}

sub _schema_boolean_to_string {
  my ($self, $schema, $depth) = @_;

  sprintf "%s, // %s\n", 'boolean', _type_description($schema);
}

sub _schema_enum_to_string {
  my ($self, $schema, $depth) = @_;

  sprintf "%s, // %s\n", 'enum', _type_description($schema, qw( enum ));
}

sub _schema_integer_to_string {
  my ($self, $schema, $depth) = @_;

  sprintf "%s, // %s\n", $schema->{format} || 'integer', _type_description($schema, qw( default ));
}

sub _schema_number_to_string {
  my ($self, $schema, $depth) = @_;

  sprintf "%s, // %s\n", $schema->{format} || 'number', _type_description($schema, qw( default ));
}

sub _schema_object_to_string {
  my ($self, $schema, $depth) = @_;
  my $description = _type_description($schema, qw( minProperties maxProperties ));
  my $str = '';

  $description = $description eq NO_DESCRIPTION ? "" : "// $description";
  $str .= _sprintf($depth == 1 ? 1 : 0, "{%s\n", $description);

  for my $k (sort keys %{$schema->{properties}}) {
    $str .= _sprintf($depth + 1, qq("%s": ), $k);
    $str .= $self->_schema_to_string_dispatch($schema->{properties}->{$k}, $depth + 1);
  }

  $str .= _sprintf($depth, "},\n");
  $str;
}

sub _schema_string_to_string {
  my ($self, $schema, $depth) = @_;

  sprintf "%s, // %s\n", $schema->{format} || 'string',
    _type_description($schema, qw( minLength maxLength pattern default ));
}

sub _schema_anyof_to_string {
  my ($self, $schema, $depth) = @_;

  my $str = '';

  $str .= "Any of the following:\n";
  foreach my $s (@{$schema->{anyOf}}) {
    $str .= _sprintf($depth + 1, "");
    $str .= $self->_schema_to_string_dispatch($s, $depth + 1);
  }

  $str;
}

sub _schema_allof_to_string {
  my ($self, $schema, $depth) = @_;

  my $str = '';

  $str .= "All of the following:\n";
  foreach my $s (@{$schema->{allOf}}) {
    $str .= _sprintf($depth + 1, "");
    $str .= $self->_schema_to_string_dispatch($s, $depth + 1);
  }

  $str;
}

sub _schema_oneof_to_string {
  my ($self, $schema, $depth) = @_;

  my $str = '';

  $str .= "One of the following:\n";
  foreach my $s (@{$schema->{oneOf}}) {
    $str .= _sprintf($depth + 1, "");
    $str .= $self->_schema_to_string_dispatch($s, $depth + 1);
  }

  $str;
}

sub _schema_to_string_dispatch {
  my ($self, $schema, $depth) = @_;
  my $required = $schema->{required};
  my $method;

  if ($required and ref $required eq 'ARRAY' and $schema->{properties}) {
    $schema->{properties}{$_}{required} = 1 for @$required;
  }

  if ($schema->{anyOf}) {
    $method = '_schema_anyof_to_string';
  } elsif ($schema->{allOf}) {
    $method = '_schema_allof_to_string';
  } elsif ($schema->{oneOf}) {
    $method = '_schema_oneof_to_string';
  } else {
    $method = '_schema_' . ($schema->{type} || 'object') . '_to_string';
  }
  return "Cannot translate '$schema->{type}' into POD." unless $self->can($method);
  return $self->$method($schema, $depth);
}

sub _summary_and_description {
  my ($self, $data) = @_;
  my $str = '';

  $str .= "$data->{summary}\n\n"     if $data->{summary};
  $str .= "$data->{description}\n\n" if $data->{description};
  $str .= NO_DESCRIPTION . "\n\n" unless $data->{summary} or $data->{description};
  $str;
}

# FUNCTIONS
sub _ascii_table {
  my ($rows, $pad) = @_;
  my $width = 1;
  my (@spec, @table);

  $pad //= '';

  for my $row (@$rows) {
    for my $i (0 .. $#$row) {
      $row->[$i] //= '';
      $row->[$i] =~ s/[\r\n]//g;
      my $len = length $row->[$i];
      $spec[$i] = $len if $len >= ($spec[$i] // 0);
    }
  }

  my $format = sprintf '%s| %s |', $pad, join ' | ', map { $width += $_ + 3; "\%-${_}s" } @spec;
  @table = map { sprintf "$format\n", @$_ } @$rows;
  unshift @table, "$pad." . ('-' x ($width - 2)) . ".\n";
  splice @table, 2, 0, "$pad|" . ('-' x ($width - 2)) . "|\n";
  push @table, "$pad'" . ('-' x ($width - 2)) . "'\n";
  return join '', @table;
}

sub _sprintf {
  my ($level, $format, @args) = @_;

  sprintf "%s$format", (" " x (($level) * 2)), @args;
}

sub _status_code_to_string {
  my ($code) = @_;
  my $message = $MOJO_MESSAGE_RESPONSE->code($code)->default_message;

  return sprintf '%s - %s', $code, $message if $message;
  return ucfirst $code;
}

sub _stringify {
  my ($k, $obj) = @_;
  return 'required' if $k eq 'required'   and $obj->{$k};
  return "$k=true"  if blessed $obj->{$k} and $obj->{$k} eq Mojo::JSON->true;
  return "$k=false" if blessed $obj->{$k} and $obj->{$k} eq Mojo::JSON->false;
  return sprintf '%s=%s', $k, encode_json $obj->{$k} if ref $obj->{$k};
  return sprintf '%s=%s', $k, $obj->{$k};
}

sub _type_description {
  my ($schema) = (shift, shift);
  return $schema->{description} if $schema->{description};
  my @keys = grep { defined $schema->{$_} } 'required', @_;
  my @description = map { _stringify($_, $schema) } @keys;

  return $schema->{title} || NO_DESCRIPTION unless @description;
  return join ', ', @description;
}

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2014, Jan Henning Thorsen

This program is free software, you can redistribute it and/or modify it under
the terms of the Artistic License version 2.0.

=head1 AUTHOR

Jan Henning Thorsen - C<jhthorsen@cpan.org>

=cut

1;
