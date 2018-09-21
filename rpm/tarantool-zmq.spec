Name: tarantool-zmq
Version: 0.1.0
Release: 1%{?dist}
Summary: ZMQ sockets for Tarantool
Group: Applications/Databases
License: BSD
URL: https://github.com/bigbes/tarantool-zmq/
Source0: https://github.com/tarantool/%{name}/archive/%{version}/%{name}-%{version}.tar.gz
BuildRequires: cmake >= 2.8
BuildRequires: gcc >= 4.5
BuildRequires: openssl-devel
BuildRequires: tarantool-devel >= 1.9.0.0
BuildRequires: zeromq-devel >= 4.0.0
Requires: tarantool >= 1.9.0.0

%description
ZMQ sockets (client/server) for Tarantool

%prep
%setup -q -n %{name}-%{version}

%build
%cmake . -DCMAKE_BUILD_TYPE=RelWithDebInfo
make %{?_smp_mflags}

## Requires MySQL
# %%check
# make %%{?_smp_mflags} check

%install
%make_install

%files
%{_libdir}/tarantool/*/
%{_datarootdir}/tarantool/*/
%doc README.md
%{!?_licensedir:%global license %doc}
%license LICENSE

%changelog
* Fri Sep 21 2018 Eugene Blikh <bigbes@gmail.com> 0.1.0-1
- Initial version of the RPM spec
