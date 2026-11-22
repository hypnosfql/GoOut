import shareLinkParserTest from './ShareLinkParser.test';
import clashYamlParserTest from './ClashYamlParser.test';
import xrayConfigBuilderTest from './XrayConfigBuilder.test';

export default function testsuite() {
  shareLinkParserTest();
  clashYamlParserTest();
  xrayConfigBuilderTest();
}
