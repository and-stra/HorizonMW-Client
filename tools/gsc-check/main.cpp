#include <xsk/stdinc.hpp>
#include <xsk/gsc/engine/h1.hpp>
#include <fstream>
#include <sstream>
#include <iostream>
static std::string root;
static std::vector<std::uint8_t> readf(const std::string& p){ std::ifstream f(p, std::ios::binary); if(!f) throw std::runtime_error("cannot open " + p); std::stringstream s; s<<f.rdbuf(); auto t=s.str(); return {t.begin(),t.end()}; }
int main(int argc, char** argv){
  if(argc<3){ std::cerr<<"usage: gsct <file.gsc> <include root>\n"; return 2; }
  root=argv[2];
  xsk::gsc::h1::context ctx;
  ctx.init(xsk::gsc::build::prod, [](std::string const& name)->std::pair<xsk::gsc::buffer,std::vector<std::uint8_t>>{
    auto n=name; for(auto& c:n) if(c=='\\') c='/';
    return {{}, readf(root + "/" + n + ".gsc")};
  });
  try {
    auto data=readf(argv[1]);
    auto assembly=ctx.compiler().compile(argv[1], data);
    auto [bytecode, stack]=ctx.assembler().assemble(*assembly);
    std::cout<<"OK: bytecode "<<bytecode.size<<" bytes, stack "<<stack.size<<" bytes\n";
  } catch(std::exception const& e){ std::cerr<<"ERROR: "<<e.what()<<"\n"; return 1; }
  return 0;
}
